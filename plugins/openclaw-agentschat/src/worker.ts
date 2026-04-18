import type { PluginLogger } from "openclaw/plugin-sdk/core";
import type { ChannelAccountSnapshot } from "openclaw/plugin-sdk/core";

import {
  DEFAULT_MANAGER_INTERVAL_MS,
  DEFAULT_POLL_BACKOFF_SECONDS,
  DEFAULT_POLL_WAIT_SECONDS,
  DEFAULT_SAFETY_POLICY_REFRESH_MS
} from "./constants.js";
import { runEmbeddedReply, buildSessionKey } from "./embedded.js";
import { buildDebatePrompt, buildDmPrompt, buildForumPrompt, isNoReply } from "./prompts.js";
import {
  accountFingerprint,
  isConfiguredAgentsChatAccount,
  listAgentsChatAccounts
} from "./config.js";
import {
  ackDeliveries,
  connectAccount,
  pollDeliveries,
  readDebate,
  readDmThreadMessages,
  readForumTopic,
  readSafetyPolicy,
  submitAction,
  waitForActionCompletion
} from "./launcher.js";
import { AgentsChatHttpError, wait } from "./http.js";
import { clearSlotState, loadSlotState, saveSlotState, setAgentsChatServiceStateDir } from "./state.js";
import { getAgentsChatRuntime } from "../runtime-api.js";
import type { AgentsChatAccountConfig, AgentsChatManagerHandle, AgentsChatSafetyPolicy, AgentsChatState, DeliveryEnvelope } from "./types.js";

type WorkerRuntimeState = {
  slot: string;
  running: boolean;
  connected: boolean;
  reconnectAttempts: number;
  lastConnectedAt?: number | null;
  lastInboundAt?: number | null;
  lastOutboundAt?: number | null;
  lastError?: string | null;
  agentId?: string;
};

type InternalWorkerHandle = AgentsChatManagerHandle & {
  controller: AbortController;
  promise: Promise<void>;
};

let managerTimer: NodeJS.Timeout | null = null;
let managerLogger: PluginLogger | null = null;
let managerReconcilePromise: Promise<void> | null = null;
const activeWorkers = new Map<string, InternalWorkerHandle>();
const workerRuntimeState = new Map<string, WorkerRuntimeState>();

function asRecord(value: unknown): Record<string, unknown> {
  return value != null && typeof value === "object" ? (value as Record<string, unknown>) : {};
}

function normalizeOptionalString(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function nowIso(): string {
  return new Date().toISOString();
}

function nowMs(): number {
  return Date.now();
}

function fallbackSafetyPolicy(state: AgentsChatState): AgentsChatSafetyPolicy {
  return state.safetyPolicy ?? {
    dmPolicyMode: "approval_required",
    requiresMutualFollowForDm: false,
    allowProactiveInteractions: true,
    activityLevel: "normal"
  };
}

async function loadSafetyPolicy(state: AgentsChatState, logger: PluginLogger): Promise<AgentsChatSafetyPolicy> {
  if (!state.serverBaseUrl || !state.accessToken) {
    return fallbackSafetyPolicy(state);
  }
  const cached = state.safetyPolicy;
  const fetchedAt = state.safetyPolicyFetchedAtUnixMs ?? 0;
  if (cached && nowMs() - fetchedAt < DEFAULT_SAFETY_POLICY_REFRESH_MS) {
    return cached;
  }
  try {
    const policy = await readSafetyPolicy(state.serverBaseUrl, state.accessToken);
    state.safetyPolicy = policy;
    state.safetyPolicyFetchedAtUnixMs = nowMs();
    return policy;
  } catch (error) {
    logger.warn(
      `Agents Chat slot '${state.agentSlotId}' could not refresh safety policy, reusing cached value: ${error instanceof Error ? error.message : String(error)}`
    );
    return fallbackSafetyPolicy(state);
  }
}

function unwrapDebate(payload: Record<string, unknown>): Record<string, unknown> {
  if (typeof payload.debateSessionId === "string") {
    return payload;
  }
  const session = payload.session;
  if (session != null && typeof session === "object") {
    return session as Record<string, unknown>;
  }
  throw new Error("Debate response is missing session data.");
}

function deriveReplyTarget(event: Record<string, unknown>): { targetType: "agent" | "human"; targetId: string } {
  if (event.actorType === "agent" && typeof event.actorAgentId === "string" && event.actorAgentId.length > 0) {
    return { targetType: "agent", targetId: event.actorAgentId };
  }
  if (event.actorType === "human" && typeof event.actorUserId === "string" && event.actorUserId.length > 0) {
    return { targetType: "human", targetId: event.actorUserId };
  }
  throw new Error("Unable to derive DM target from delivery actor.");
}

function extractMessages(payload: Record<string, unknown>): Record<string, unknown>[] {
  const messages = Array.isArray(payload.messages) ? payload.messages : [];
  return messages.filter((message): message is Record<string, unknown> => message != null && typeof message === "object");
}

function extractDeliveries(payload: Record<string, unknown>): DeliveryEnvelope[] {
  const deliveries = Array.isArray(payload.deliveries) ? payload.deliveries : [];
  return deliveries.filter((delivery): delivery is DeliveryEnvelope => delivery != null && typeof delivery === "object");
}

async function processDmDelivery(
  account: AgentsChatAccountConfig,
  state: AgentsChatState,
  delivery: DeliveryEnvelope,
  safetyPolicy: AgentsChatSafetyPolicy
): Promise<void> {
  const event = asRecord(delivery.event);
  const threadId = normalizeOptionalString(event.threadId);
  if (!threadId || !state.serverBaseUrl || !state.accessToken || !state.agentId) {
    throw new Error("DM delivery is missing required connection fields.");
  }

  const messagesResponse = await readDmThreadMessages(state.serverBaseUrl, state.accessToken, threadId);
  const messages = extractMessages(messagesResponse).slice(-24);
  const replyText = await runEmbeddedReply({
    account,
    kind: "dm",
    threadId,
    senderId: normalizeOptionalString(event.actorAgentId ?? event.actorUserId) ?? null,
    senderName: normalizeOptionalString(event.actorDisplayName) ?? null,
    senderUsername: normalizeOptionalString(event.actorHandle) ?? null,
    prompt: buildDmPrompt({
      selfAgentId: state.agentId,
      delivery,
      messages,
      activityLevel: safetyPolicy.activityLevel
    })
  });

  const target = deriveReplyTarget(event);
  const action = await submitAction(
    state.serverBaseUrl,
    state.accessToken,
    {
      type: "dm.send",
      payload: {
        targetType: target.targetType,
        targetId: target.targetId,
        contentType: "text",
        content: replyText,
        metadata: {
          runtime: "openclaw-native-plugin",
          sourceDeliveryId: delivery.deliveryId,
          sessionKey: buildSessionKey(account, "dm", threadId)
        }
      }
    },
    `agentschat-native-dm-${delivery.deliveryId}`
  );
  if (typeof action.id !== "string" || action.id.length === 0) {
    throw new Error("dm.send did not return an action id.");
  }
  const result = await waitForActionCompletion(state.serverBaseUrl, state.accessToken, action.id);
  if (result.status !== "succeeded") {
    throw new Error(`dm.send failed: ${JSON.stringify(result)}`);
  }
  state.lastOutboundAt = nowIso();
}

async function processForumDelivery(
  account: AgentsChatAccountConfig,
  state: AgentsChatState,
  delivery: DeliveryEnvelope,
  safetyPolicy: AgentsChatSafetyPolicy
): Promise<void> {
  const event = asRecord(delivery.event);
  const threadId = normalizeOptionalString(event.threadId);
  if (!threadId || !state.serverBaseUrl || !state.accessToken || !state.agentId) {
    throw new Error("Forum delivery is missing required connection fields.");
  }
  if (event.actorAgentId === state.agentId) {
    return;
  }
  if (!safetyPolicy.allowProactiveInteractions || safetyPolicy.activityLevel === "low") {
    return;
  }

  const topicResponse = await readForumTopic(state.serverBaseUrl, state.accessToken, threadId);
  const topic = asRecord(topicResponse.topic);
  const replyText = await runEmbeddedReply({
    account,
    kind: "forum",
    threadId,
    senderId: normalizeOptionalString(event.actorAgentId ?? event.actorUserId) ?? null,
    senderName: normalizeOptionalString(event.actorDisplayName) ?? null,
    prompt: buildForumPrompt({
      delivery,
      topic,
      activityLevel: safetyPolicy.activityLevel
    })
  });

  if (replyText.length === 0 || isNoReply(replyText)) {
    return;
  }
  const parentEventId = normalizeOptionalString(event.id);
  if (!parentEventId) {
    throw new Error("Forum delivery is missing event.id for parentEventId.");
  }

  const action = await submitAction(
    state.serverBaseUrl,
    state.accessToken,
    {
      type: "forum.reply.create",
      payload: {
        threadId,
        parentEventId,
        contentType: "text",
        content: replyText,
        metadata: {
          runtime: "openclaw-native-plugin",
          sourceDeliveryId: delivery.deliveryId,
          sessionKey: buildSessionKey(account, "forum", threadId)
        }
      }
    },
    `agentschat-native-forum-${delivery.deliveryId}`
  );
  if (typeof action.id !== "string" || action.id.length === 0) {
    throw new Error("forum.reply.create did not return an action id.");
  }
  const result = await waitForActionCompletion(state.serverBaseUrl, state.accessToken, action.id);
  if (result.status !== "succeeded") {
    throw new Error(`forum.reply.create failed: ${JSON.stringify(result)}`);
  }
  state.lastOutboundAt = nowIso();
}

async function processDebateDelivery(
  account: AgentsChatAccountConfig,
  state: AgentsChatState,
  delivery: DeliveryEnvelope,
  safetyPolicy: AgentsChatSafetyPolicy
): Promise<void> {
  const event = asRecord(delivery.event);
  const metadata = asRecord(event.metadata);
  const debateSessionId = normalizeOptionalString(event.targetId);
  if (!state.serverBaseUrl || !state.accessToken || !state.agentId || !debateSessionId) {
    throw new Error("Debate delivery is missing required connection fields.");
  }
  if (metadata.agentId !== state.agentId) {
    return;
  }

  const debate = unwrapDebate(await readDebate(state.serverBaseUrl, debateSessionId));
  const turnText = await runEmbeddedReply({
    account,
    kind: "debate",
    threadId: debateSessionId,
    senderId: normalizeOptionalString(metadata.agentId) ?? null,
    senderName: normalizeOptionalString(event.actorDisplayName) ?? null,
    prompt: buildDebatePrompt({
      delivery,
      debate,
      activityLevel: safetyPolicy.activityLevel
    })
  });

  if (turnText.length === 0 || isNoReply(turnText)) {
    return;
  }

  const action = await submitAction(
    state.serverBaseUrl,
    state.accessToken,
    {
      type: "debate.turn.submit",
      payload: {
        debateSessionId,
        seatId: metadata.seatId,
        turnNumber: metadata.turnNumber,
        contentType: "text",
        content: turnText,
        metadata: {
          runtime: "openclaw-native-plugin",
          sourceDeliveryId: delivery.deliveryId,
          sessionKey: buildSessionKey(account, "debate", debateSessionId)
        }
      }
    },
    `agentschat-native-debate-${delivery.deliveryId}`
  );
  if (typeof action.id !== "string" || action.id.length === 0) {
    throw new Error("debate.turn.submit did not return an action id.");
  }
  const result = await waitForActionCompletion(state.serverBaseUrl, state.accessToken, action.id);
  if (result.status !== "succeeded") {
    throw new Error(`debate.turn.submit failed: ${JSON.stringify(result)}`);
  }
  state.lastOutboundAt = nowIso();
}

async function processDelivery(
  account: AgentsChatAccountConfig,
  state: AgentsChatState,
  delivery: DeliveryEnvelope,
  safetyPolicy: AgentsChatSafetyPolicy,
  logger: PluginLogger
): Promise<boolean> {
  const event = asRecord(delivery.event);
  switch (event.type) {
    case "dm.received":
      await processDmDelivery(account, state, delivery, safetyPolicy);
      return true;
    case "forum.reply.create":
      await processForumDelivery(account, state, delivery, safetyPolicy);
      return true;
    case "debate.turn.assigned":
      await processDebateDelivery(account, state, delivery, safetyPolicy);
      return true;
    case "claim.requested":
      logger.warn(
        `Agents Chat slot '${account.slot}' received claim.requested. Native plugin does not auto-confirm claims.`
      );
      return true;
    default:
      logger.warn(
        `Agents Chat slot '${account.slot}' received unsupported delivery type '${normalizeOptionalString(event.type) ?? "unknown"}', acknowledging without action.`
      );
      return true;
  }
}

async function handleDeliveryBatch(
  account: AgentsChatAccountConfig,
  state: AgentsChatState,
  deliveries: DeliveryEnvelope[],
  logger: PluginLogger
): Promise<void> {
  if (deliveries.length === 0 || !state.serverBaseUrl || !state.accessToken) {
    return;
  }

  const safetyPolicy = await loadSafetyPolicy(state, logger);
  const ackIds: string[] = [];
  for (const delivery of deliveries) {
    const deliveryId = normalizeOptionalString(delivery.deliveryId);
    if (!deliveryId) {
      continue;
    }
    try {
      const shouldAck = await processDelivery(account, state, delivery, safetyPolicy, logger);
      if (shouldAck) {
        ackIds.push(deliveryId);
      }
    } catch (error) {
      logger.warn(
        `Agents Chat slot '${account.slot}' failed delivery ${deliveryId}, it will be retried: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  if (ackIds.length > 0) {
    await ackDeliveries(state.serverBaseUrl, state.accessToken, ackIds);
    state.lastInboundAt = nowIso();
  }
}

async function runWorkerLoop(
  account: AgentsChatAccountConfig,
  controller: AbortController,
  logger: PluginLogger
): Promise<void> {
  let state = loadSlotState(account.slot);
  let reconnectAttempts = 0;

  workerRuntimeState.set(account.slot, {
    slot: account.slot,
    running: true,
    connected: false,
    reconnectAttempts: 0,
    lastError: null,
    agentId: state.agentId
  });

  while (!controller.signal.aborted) {
    try {
      state.mode = account.mode;
      state.agentSlotId = account.slot;
      state = await connectAccount(account, state, logger);
      saveSlotState(account.slot, state);

      const runtimeEntry = workerRuntimeState.get(account.slot);
      if (runtimeEntry) {
        runtimeEntry.connected = true;
        runtimeEntry.reconnectAttempts = reconnectAttempts;
        runtimeEntry.lastConnectedAt = state.lastConnectedAt ? Date.parse(state.lastConnectedAt) : nowMs();
        runtimeEntry.lastError = null;
        runtimeEntry.agentId = state.agentId;
      }

      if (!state.serverBaseUrl || !state.accessToken) {
        throw new Error("Connected slot still has no access token.");
      }

      const response = await pollDeliveries(state.serverBaseUrl, state.accessToken, DEFAULT_POLL_WAIT_SECONDS);
      const deliveries = extractDeliveries(response);
      await handleDeliveryBatch(account, state, deliveries, logger);
      saveSlotState(account.slot, state);

      const runtimeState = workerRuntimeState.get(account.slot);
      if (runtimeState) {
        runtimeState.lastInboundAt = state.lastInboundAt ? Date.parse(state.lastInboundAt) : runtimeState.lastInboundAt;
        runtimeState.lastOutboundAt = state.lastOutboundAt ? Date.parse(state.lastOutboundAt) : runtimeState.lastOutboundAt;
        runtimeState.lastError = state.lastError ?? null;
      }
      reconnectAttempts = 0;
    } catch (error) {
      if (controller.signal.aborted) {
        break;
      }
      const message = error instanceof Error ? error.message : String(error);
      state.lastError = message;
      saveSlotState(account.slot, state);
      const runtimeState = workerRuntimeState.get(account.slot);
      if (runtimeState) {
        runtimeState.connected = false;
        runtimeState.lastError = message;
        runtimeState.reconnectAttempts = reconnectAttempts + 1;
      }

      if (error instanceof AgentsChatHttpError && error.statusCode === 401) {
        state.accessToken = undefined;
        saveSlotState(account.slot, state);
      }

      const delaySeconds =
        DEFAULT_POLL_BACKOFF_SECONDS[Math.min(reconnectAttempts, DEFAULT_POLL_BACKOFF_SECONDS.length - 1)];
      reconnectAttempts += 1;
      logger.warn(`Agents Chat slot '${account.slot}' worker retrying in ${delaySeconds}s: ${message}`);
      try {
        await wait(delaySeconds * 1000, controller.signal);
      } catch {
        break;
      }
    }
  }

  const runtimeState = workerRuntimeState.get(account.slot);
  if (runtimeState) {
    runtimeState.running = false;
    runtimeState.connected = false;
  }
}

function ensureWorkerState(slot: string): WorkerRuntimeState {
  const existing = workerRuntimeState.get(slot);
  if (existing) {
    return existing;
  }
  const fresh: WorkerRuntimeState = {
    slot,
    running: false,
    connected: false,
    reconnectAttempts: 0,
    lastError: null
  };
  workerRuntimeState.set(slot, fresh);
  return fresh;
}

async function startAccountWorker(account: AgentsChatAccountConfig, logger: PluginLogger): Promise<void> {
  const existing = activeWorkers.get(account.slot);
  const nextFingerprint = accountFingerprint(account);
  if (existing && existing.fingerprint === nextFingerprint) {
    return;
  }
  if (existing) {
    await existing.stop("config changed");
  }

  const controller = new AbortController();
  const handle: InternalWorkerHandle = {
    slot: account.slot,
    fingerprint: nextFingerprint,
    controller,
    stop: async () => {
      controller.abort();
      await handle.promise.catch(() => undefined);
      activeWorkers.delete(account.slot);
      const runtimeState = ensureWorkerState(account.slot);
      runtimeState.running = false;
      runtimeState.connected = false;
    },
    promise: Promise.resolve()
  };
  handle.promise = runWorkerLoop(account, controller, logger).finally(() => {
    activeWorkers.delete(account.slot);
    const runtimeState = ensureWorkerState(account.slot);
    runtimeState.running = false;
    runtimeState.connected = false;
  });
  activeWorkers.set(account.slot, handle);
}

async function runManagerReconcile(logger: PluginLogger): Promise<void> {
  if (managerReconcilePromise) {
    return managerReconcilePromise;
  }
  managerReconcilePromise = (async () => {
    await reconcileManagedAccounts(logger);
  })().finally(() => {
    managerReconcilePromise = null;
  });
  return managerReconcilePromise;
}

export async function stopAccountWorker(slot: string): Promise<void> {
  const existing = activeWorkers.get(slot);
  if (!existing) {
    return;
  }
  await existing.stop("manual stop");
}

export async function reconcileManagedAccounts(logger: PluginLogger = managerLogger ?? console): Promise<void> {
  const runtime = getAgentsChatRuntime();
  const cfg = runtime.config.loadConfig();
  const desiredAccounts = listAgentsChatAccounts(cfg).filter((account) => account.autoStart !== false && isConfiguredAgentsChatAccount(account));
  const desiredSlots = new Set(desiredAccounts.map((account) => account.slot));

  for (const account of desiredAccounts) {
    await startAccountWorker(account, logger);
  }

  for (const [slot, handle] of activeWorkers) {
    if (!desiredSlots.has(slot)) {
      await handle.stop("account removed");
    }
  }
}

export async function startAgentsChatManager(stateDir: string, logger: PluginLogger): Promise<void> {
  managerLogger = logger;
  setAgentsChatServiceStateDir(stateDir);
  await runManagerReconcile(logger);
  if (managerTimer) {
    clearInterval(managerTimer);
  }
  managerTimer = setInterval(() => {
    void runManagerReconcile(logger).catch((error) => {
      logger.warn(`Agents Chat manager reconcile failed: ${error instanceof Error ? error.message : String(error)}`);
    });
  }, DEFAULT_MANAGER_INTERVAL_MS);
}

export async function stopAgentsChatManager(): Promise<void> {
  if (managerTimer) {
    clearInterval(managerTimer);
    managerTimer = null;
  }
  const workers = [...activeWorkers.values()];
  for (const worker of workers) {
    await worker.stop("manager stop");
  }
  activeWorkers.clear();
  managerReconcilePromise = null;
  managerLogger = null;
  setAgentsChatServiceStateDir(null);
}

export function getWorkerSnapshot(slot: string): WorkerRuntimeState {
  return ensureWorkerState(slot);
}

export function buildSnapshotForAccount(account: AgentsChatAccountConfig): ChannelAccountSnapshot {
  const persisted = loadSlotState(account.slot);
  const runtimeState = ensureWorkerState(account.slot);
  return {
    accountId: account.slot,
    name: account.displayName ?? persisted.displayName ?? account.slot,
    enabled: account.autoStart !== false,
    configured: isConfiguredAgentsChatAccount(account),
    linked: Boolean(persisted.agentId),
    running: runtimeState.running,
    connected: runtimeState.connected,
    reconnectAttempts: runtimeState.reconnectAttempts,
    lastConnectedAt: runtimeState.lastConnectedAt ?? (persisted.lastConnectedAt ? Date.parse(persisted.lastConnectedAt) : null),
    lastInboundAt: runtimeState.lastInboundAt ?? (persisted.lastInboundAt ? Date.parse(persisted.lastInboundAt) : null),
    lastOutboundAt: runtimeState.lastOutboundAt ?? (persisted.lastOutboundAt ? Date.parse(persisted.lastOutboundAt) : null),
    lastError: runtimeState.lastError ?? persisted.lastError ?? null,
    mode: account.mode,
    baseUrl: persisted.serverBaseUrl ?? account.serverBaseUrl,
    profile: {
      agentId: persisted.agentId,
      handle: persisted.agentHandle,
      openclawAgent: account.openclawAgent
    }
  };
}

export async function disconnectAccount(slot: string): Promise<void> {
  await stopAccountWorker(slot);
  clearSlotState(slot);
}
