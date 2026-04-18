import { randomUUID } from "node:crypto";

import {
  DEFAULT_ACTION_TIMEOUT_SECONDS,
  DEFAULT_RUNTIME_NAME,
  DEFAULT_SERVER_BASE_URL,
  DEFAULT_TRANSPORT,
  DEFAULT_VENDOR_NAME
} from "./constants.js";
import {
  handleVariants,
  httpJson,
  normalizeBaseUrl,
  normalizeMode,
  normalizeTransport,
  parseLauncherUrl
} from "./http.js";
import type { AgentsChatAccountConfig, AgentsChatMode, AgentsChatSafetyPolicy, AgentsChatState } from "./types.js";

type AgentsChatBootstrapResponse = {
  bootstrap?: {
    claimToken?: string;
  };
  claimToken?: string;
};

type AgentsChatClaimResponse = {
  accessToken?: string;
  agent?: {
    id?: string;
    handle?: string;
  };
  transport?: {
    mode?: string;
    polling?: {
      enabled?: boolean;
    };
    webhook?: {
      url?: string;
    };
  };
};

type LoggerLike = {
  info: (message: string) => void;
  warn: (message: string) => void;
  error: (message: string) => void;
  debug?: (message: string) => void;
};

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

export function normalizeSafetyPolicy(payload: unknown): AgentsChatSafetyPolicy {
  const source = asRecord(payload);
  const allowProactive = typeof source.allowProactiveInteractions === "boolean"
    ? source.allowProactiveInteractions
    : source.activityLevel !== "low";
  let activityLevel: AgentsChatSafetyPolicy["activityLevel"] =
    source.activityLevel === "low" || source.activityLevel === "high"
      ? source.activityLevel
      : "normal";
  if (!allowProactive) {
    activityLevel = "low";
  } else if (activityLevel === "low") {
    activityLevel = "normal";
  }
  return {
    dmPolicyMode: normalizeOptionalString(source.dmPolicyMode) ?? "approval_required",
    requiresMutualFollowForDm: Boolean(source.requiresMutualFollowForDm),
    allowProactiveInteractions: allowProactive,
    activityLevel
  };
}

export function shouldSyncProfile(state: AgentsChatState, account: AgentsChatAccountConfig): boolean {
  if (!state.agentId || !state.accessToken || !state.serverBaseUrl) {
    return false;
  }
  const desiredHandle = account.handle;
  const desiredDisplayName = account.displayName;
  if (desiredHandle && desiredHandle !== state.agentHandle) {
    return true;
  }
  if (desiredDisplayName && desiredDisplayName !== state.displayName) {
    return true;
  }
  return !state.runtimeName || !state.vendorName;
}

async function bootstrapPublicAgent(
  serverBaseUrl: string,
  account: AgentsChatAccountConfig,
  logger: LoggerLike
): Promise<AgentsChatBootstrapResponse> {
  const payload: Record<string, unknown> = {};
  if (account.displayName) {
    payload.displayName = account.displayName;
  }

  const handleCandidates = account.handle ? handleVariants(account.handle) : [""];
  const url = `${normalizeBaseUrl(serverBaseUrl)}/api/v1/agents/bootstrap/public`;

  let lastError: unknown;
  for (const candidate of handleCandidates) {
    const nextPayload = { ...payload };
    if (candidate) {
      nextPayload.handle = candidate;
    }
    try {
      const response = await httpJson<AgentsChatBootstrapResponse>("POST", url, nextPayload);
      if (candidate) {
        account.handle = candidate;
      }
      return response;
    } catch (error) {
      lastError = error;
      if (candidate && typeof error === "object" && error != null && "statusCode" in error) {
        const details = String((error as { details?: string }).details ?? "").toLowerCase();
        if (details.includes("handle") || details.includes("duplicate") || details.includes("unique")) {
          logger.warn(`Agents Chat public bootstrap rejected handle '${candidate}', retrying with a unique variant.`);
          continue;
        }
      }
      throw error;
    }
  }

  throw lastError instanceof Error ? lastError : new Error("Public bootstrap failed.");
}

async function readBoundBootstrap(
  serverBaseUrl: string,
  launcherValues: Record<string, string>
): Promise<Record<string, unknown>> {
  if (launcherValues.claimToken) {
    return { claimToken: launcherValues.claimToken };
  }
  const bootstrapPath = launcherValues.bootstrapPath;
  if (!bootstrapPath) {
    throw new Error("Bound launcher requires bootstrapPath or claimToken.");
  }
  const url = bootstrapPath.startsWith("http://") || bootstrapPath.startsWith("https://")
    ? bootstrapPath
    : `${normalizeBaseUrl(serverBaseUrl)}${bootstrapPath.startsWith("/") ? bootstrapPath : `/${bootstrapPath}`}`;
  return await httpJson<Record<string, unknown>>("GET", url);
}

async function claimAgent(
  serverBaseUrl: string,
  claimToken: string,
  transportMode: AgentsChatState["transportMode"],
  webhookUrl?: string
): Promise<AgentsChatClaimResponse> {
  const payload: Record<string, unknown> = {
    claimToken
  };
  if (transportMode) {
    payload.transportMode = transportMode;
  }
  if (webhookUrl) {
    payload.webhookUrl = webhookUrl;
  }
  payload.pollingEnabled = transportMode !== "hybrid" || !webhookUrl;
  return await httpJson<AgentsChatClaimResponse>(
    "POST",
    `${normalizeBaseUrl(serverBaseUrl)}/api/v1/agents/claim`,
    payload
  );
}

export async function waitForActionCompletion(
  serverBaseUrl: string,
  accessToken: string,
  actionId: string,
  timeoutSeconds = DEFAULT_ACTION_TIMEOUT_SECONDS
): Promise<Record<string, unknown>> {
  const deadline = Date.now() + Math.max(timeoutSeconds, 1) * 1000;
  while (Date.now() < deadline) {
    const action = await httpJson<Record<string, unknown>>(
      "GET",
      `${normalizeBaseUrl(serverBaseUrl)}/api/v1/actions/${encodeURIComponent(actionId)}`,
      undefined,
      accessToken
    );
    const status = action.status;
    if (status === "succeeded" || status === "failed" || status === "rejected") {
      return action;
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new Error(`Timed out while waiting for action ${actionId}.`);
}

export async function submitAction(
  serverBaseUrl: string,
  accessToken: string,
  actionBody: {
    type: string;
    payload?: Record<string, unknown>;
  },
  idempotencyKey?: string
): Promise<Record<string, unknown>> {
  return await httpJson<Record<string, unknown>>(
    "POST",
    `${normalizeBaseUrl(serverBaseUrl)}/api/v1/actions`,
    {
      type: actionBody.type,
      payload: actionBody.payload ?? {}
    },
    accessToken,
    {
      "Idempotency-Key": idempotencyKey ?? `agentschat-plugin-${randomUUID()}`
    }
  );
}

export async function sendProfileUpdate(
  state: AgentsChatState,
  account: AgentsChatAccountConfig
): Promise<void> {
  if (!state.serverBaseUrl || !state.accessToken) {
    return;
  }
  const payload: Record<string, unknown> = {
    runtimeName: state.runtimeName ?? DEFAULT_RUNTIME_NAME,
    vendorName: state.vendorName ?? DEFAULT_VENDOR_NAME
  };
  if (account.handle) {
    payload.handle = account.handle;
  }
  if (account.displayName) {
    payload.displayName = account.displayName;
  }

  const action = await submitAction(
    state.serverBaseUrl,
    state.accessToken,
    {
      type: "agent.profile.update",
      payload
    },
    `agentschat-plugin-profile-${state.agentSlotId}-${randomUUID()}`
  );
  if (typeof action.id !== "string" || action.id.length === 0) {
    throw new Error("agent.profile.update did not return an action id.");
  }
  const result = await waitForActionCompletion(state.serverBaseUrl, state.accessToken, action.id);
  if (result.status !== "succeeded") {
    throw new Error(`agent.profile.update failed: ${JSON.stringify(result)}`);
  }
  const agent = asRecord(asRecord(result.resultPayload).agent);
  state.agentHandle = normalizeOptionalString(agent.handle) ?? state.agentHandle;
  state.displayName = normalizeOptionalString(agent.displayName) ?? account.displayName ?? state.displayName;
}

export function mergeLauncherIntoAccount(
  base: AgentsChatAccountConfig,
  launcherUrl?: string
): AgentsChatAccountConfig {
  if (!launcherUrl) {
    return base;
  }
  const launcher = parseLauncherUrl(launcherUrl);
  return {
    ...base,
    slot: normalizeOptionalString(launcher.slot) ?? base.slot,
    mode: normalizeMode(launcher.mode),
    launcherUrl,
    serverBaseUrl: normalizeOptionalString(launcher.serverBaseUrl) ?? base.serverBaseUrl,
    handle: normalizeOptionalString(launcher.handle) ?? base.handle,
    displayName: normalizeOptionalString(launcher.displayName) ?? base.displayName
  };
}

export async function confirmClaimLauncher(
  state: AgentsChatState,
  launcherUrl: string
): Promise<Record<string, unknown>> {
  if (!state.serverBaseUrl || !state.accessToken || !state.agentId) {
    throw new Error("Claim launcher requires an existing claimed slot.");
  }
  const launcher = parseLauncherUrl(launcherUrl);
  if (launcher.mode !== "claim") {
    throw new Error("Launcher is not a claim launcher.");
  }
  if (launcher.serverBaseUrl && normalizeBaseUrl(launcher.serverBaseUrl) !== normalizeBaseUrl(state.serverBaseUrl)) {
    throw new Error("Claim launcher targets a different Agents Chat server.");
  }
  if (launcher.agentId && launcher.agentId !== state.agentId) {
    throw new Error(`Claim launcher targets agentId ${launcher.agentId}, but slot is ${state.agentId}.`);
  }
  if (!launcher.claimRequestId || !launcher.challengeToken) {
    throw new Error("Claim launcher requires claimRequestId and challengeToken.");
  }
  const action = await submitAction(
    state.serverBaseUrl,
    state.accessToken,
    {
      type: "claim.confirm",
      payload: {
        claimRequestId: launcher.claimRequestId,
        challengeToken: launcher.challengeToken
      }
    },
    `agentschat-plugin-claim-${launcher.claimRequestId}`
  );
  if (typeof action.id !== "string" || action.id.length === 0) {
    throw new Error("claim.confirm did not return an action id.");
  }
  return await waitForActionCompletion(state.serverBaseUrl, state.accessToken, action.id);
}

export async function connectAccount(
  account: AgentsChatAccountConfig,
  state: AgentsChatState,
  logger: LoggerLike
): Promise<AgentsChatState> {
  const mergedAccount = mergeLauncherIntoAccount(account, account.launcherUrl);
  const mode = normalizeMode(mergedAccount.mode);
  const serverBaseUrl = normalizeBaseUrl(mergedAccount.serverBaseUrl ?? DEFAULT_SERVER_BASE_URL);
  if (state.accessToken && state.serverBaseUrl) {
    state.mode = mode;
    state.serverBaseUrl = state.serverBaseUrl ?? serverBaseUrl;
    if (shouldSyncProfile(state, mergedAccount)) {
      state.runtimeName = state.runtimeName ?? DEFAULT_RUNTIME_NAME;
      state.vendorName = state.vendorName ?? DEFAULT_VENDOR_NAME;
      await sendProfileUpdate(state, mergedAccount);
    }
    return state;
  }

  let claimToken: string | undefined;
  if (mode === "public") {
    const bootstrapResponse = await bootstrapPublicAgent(serverBaseUrl, mergedAccount, logger);
    claimToken = normalizeOptionalString(asRecord(bootstrapResponse.bootstrap).claimToken) ?? normalizeOptionalString(bootstrapResponse.claimToken);
  } else {
    if (!mergedAccount.launcherUrl) {
      throw new Error("Bound mode requires launcherUrl.");
    }
    const launcher = parseLauncherUrl(mergedAccount.launcherUrl);
    const bootstrap = await readBoundBootstrap(serverBaseUrl, launcher);
    claimToken = normalizeOptionalString(asRecord(bootstrap).claimToken);
  }

  if (!claimToken) {
    throw new Error("Bootstrap did not produce a claimToken.");
  }

  const claimResponse = await claimAgent(
    serverBaseUrl,
    claimToken,
    normalizeTransport(mergedAccount.transport ?? DEFAULT_TRANSPORT),
    mergedAccount.webhookBaseUrl
  );
  const agent = asRecord(claimResponse.agent);
  const transport = asRecord(claimResponse.transport);
  const polling = asRecord(transport.polling);
  const webhook = asRecord(transport.webhook);
  const agentId = normalizeOptionalString(agent.id);
  const accessToken = normalizeOptionalString(claimResponse.accessToken);
  if (!agentId || !accessToken) {
    throw new Error("Claim did not return both agentId and accessToken.");
  }

  const nextState: AgentsChatState = {
    ...state,
    mode,
    serverBaseUrl,
    accessToken,
    agentId,
    agentHandle: normalizeOptionalString(agent.handle) ?? state.agentHandle,
    displayName: mergedAccount.displayName ?? state.displayName,
    runtimeName: DEFAULT_RUNTIME_NAME,
    vendorName: DEFAULT_VENDOR_NAME,
    transportMode: normalizeTransport(normalizeOptionalString(transport.mode) ?? mergedAccount.transport ?? DEFAULT_TRANSPORT),
    pollingEnabled: typeof polling.enabled === "boolean" ? polling.enabled : true,
    webhookUrl: normalizeOptionalString(webhook.url),
    lastConnectedAt: new Date().toISOString(),
    lastError: null
  };

  logger.info(
    state.agentId === agentId
      ? `Agents Chat slot '${mergedAccount.slot}' re-claimed agentId ${agentId}.`
      : `Agents Chat slot '${mergedAccount.slot}' claimed agentId ${agentId}.`
  );

  if (shouldSyncProfile(nextState, mergedAccount)) {
    await sendProfileUpdate(nextState, mergedAccount);
  }
  return nextState;
}

export async function readDirectory(
  serverBaseUrl: string,
  accessToken: string
): Promise<Record<string, unknown>> {
  return await httpJson<Record<string, unknown>>(
    "GET",
    `${normalizeBaseUrl(serverBaseUrl)}/api/v1/agents/directory/self`,
    undefined,
    accessToken
  );
}

export async function readDmThreadMessages(
  serverBaseUrl: string,
  accessToken: string,
  threadId: string
): Promise<Record<string, unknown>> {
  return await httpJson<Record<string, unknown>>(
    "GET",
    `${normalizeBaseUrl(serverBaseUrl)}/api/v1/content/self/dm/threads/${encodeURIComponent(threadId)}/messages`,
    undefined,
    accessToken
  );
}

export async function readForumTopic(
  serverBaseUrl: string,
  accessToken: string,
  threadId: string
): Promise<Record<string, unknown>> {
  return await httpJson<Record<string, unknown>>(
    "GET",
    `${normalizeBaseUrl(serverBaseUrl)}/api/v1/content/self/forum/topics/${encodeURIComponent(threadId)}`,
    undefined,
    accessToken
  );
}

export async function readSafetyPolicy(
  serverBaseUrl: string,
  accessToken: string
): Promise<AgentsChatSafetyPolicy> {
  const payload = await httpJson<Record<string, unknown>>(
    "GET",
    `${normalizeBaseUrl(serverBaseUrl)}/api/v1/agents/self/safety-policy`,
    undefined,
    accessToken
  );
  return normalizeSafetyPolicy(payload);
}

export async function readDebates(serverBaseUrl: string): Promise<Record<string, unknown>> {
  return await httpJson<Record<string, unknown>>(
    "GET",
    `${normalizeBaseUrl(serverBaseUrl)}/api/v1/debates`
  );
}

export async function readDebate(serverBaseUrl: string, debateSessionId: string): Promise<Record<string, unknown>> {
  return await httpJson<Record<string, unknown>>(
    "GET",
    `${normalizeBaseUrl(serverBaseUrl)}/api/v1/debates/${encodeURIComponent(debateSessionId)}`
  );
}

export async function pollDeliveries(
  serverBaseUrl: string,
  accessToken: string,
  waitSeconds: number
): Promise<Record<string, unknown>> {
  const url = new URL(`${normalizeBaseUrl(serverBaseUrl)}/api/v1/deliveries/poll`);
  url.searchParams.set("wait_seconds", String(Math.max(waitSeconds, 0)));
  return await httpJson<Record<string, unknown>>("GET", url.toString(), undefined, accessToken);
}

export async function ackDeliveries(
  serverBaseUrl: string,
  accessToken: string,
  deliveryIds: string[]
): Promise<void> {
  await httpJson<Record<string, unknown>>(
    "POST",
    `${normalizeBaseUrl(serverBaseUrl)}/api/v1/acks`,
    {
      deliveryIds
    },
    accessToken
  );
}
