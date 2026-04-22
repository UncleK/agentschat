import { resolve as resolvePath } from "node:path";

import type { OpenClawConfig } from "openclaw/plugin-sdk/core";

import type { AgentsChatRuntimeContext } from "./context.js";
import { DEFAULT_SERVER_BASE_URL, DEFAULT_TRANSPORT } from "./constants.js";
import { draftInitialPublicProfile } from "./embedded.js";
import {
  describeAgentsChatAccountConfiguredState,
  findAgentsChatAccount,
  listAgentsChatAccounts,
  removeAgentsChatAccount,
  upsertAgentsChatAccount
} from "./config.js";
import { normalizeMode, normalizeSlot, parseLauncherUrl } from "./http.js";
import {
  confirmClaimLauncher,
  connectAccount,
  isBootstrapCapableAccount,
  isResumeCapableState,
  pollDeliveries,
  readDebates,
  readSafetyPolicy,
  mergeLauncherIntoAccount
} from "./launcher.js";
import {
  clearWorkerConflict,
  disconnectAccount,
  getWorkerSnapshot,
  reconcileManagedAccounts
} from "./worker.js";
import {
  inspectLegacyStateSources,
  loadSlotState,
  migrateLegacyStateIfNeeded,
  resolveDefaultPluginStateRoot,
  resolveSlotStateFilePath,
  saveSlotState
} from "./state.js";
import type { AgentsChatAccountConfig, AgentsChatActivityLevel, ConnectAccountInput } from "./types.js";

type OpenClawPluginCliContext = {
  program: {
    command: (name: string) => any;
  };
  config: OpenClawConfig;
  workspaceDir?: string;
  logger: {
    debug?: (message: string) => void;
    info: (message: string) => void;
    warn: (message: string) => void;
    error: (message: string) => void;
  };
};

function asJson(value: unknown): string {
  return JSON.stringify(value, null, 2);
}

function boolOption(value: string | undefined, previous?: boolean): boolean {
  if (value == null) {
    return previous ?? true;
  }
  return value !== "false";
}

function collectStringOption(value: string, previous: string[] = []): string[] {
  const trimmed = value.trim();
  if (!trimmed) {
    return previous;
  }
  return [...previous, trimmed];
}

function nowIso(): string {
  return new Date().toISOString();
}

function toUnixMs(value?: string | null): number | null {
  if (!value) {
    return null;
  }
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? null : parsed;
}

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

function uniqueStrings(values: Array<string | undefined>): string[] {
  return values.filter((value, index, source): value is string => Boolean(value) && source.indexOf(value) === index);
}

function normalizeComparablePath(value: string): string {
  return resolvePath(value).replace(/\\/g, "/").replace(/\/+$/g, "").toLowerCase();
}

function pathMatchesRoot(currentPath: string, candidateRoot: string): boolean {
  return currentPath === candidateRoot || currentPath.startsWith(`${candidateRoot}/`);
}

function listConfiguredOpenClawAgentIds(cfg: OpenClawConfig): string[] {
  const list = Array.isArray(cfg.agents?.list) ? cfg.agents.list : [];
  return uniqueStrings(
    list.map((entry) => normalizeOptionalString(asRecord(entry).id))
  );
}

function formatKnownAgentIds(agentIds: string[]): string {
  if (agentIds.length === 0) {
    return "none";
  }
  return agentIds.map((agentId) => `'${agentId}'`).join(", ");
}

function validateKnownOpenClawAgentId(cfg: OpenClawConfig, agentId: string): void {
  const knownAgentIds = listConfiguredOpenClawAgentIds(cfg);
  if (knownAgentIds.length === 0 || knownAgentIds.includes(agentId)) {
    return;
  }
  throw new Error(
    `OpenClaw agent '${agentId}' was not found in the local config. Known local agents: ${formatKnownAgentIds(knownAgentIds)}.`
  );
}

function inferOpenClawAgentIdFromWorkspace(
  runtimeContext: AgentsChatRuntimeContext,
  ctx: OpenClawPluginCliContext,
  cfg: OpenClawConfig
): {
  agentId: string;
  reason: string;
} | null {
  const knownAgentIds = listConfiguredOpenClawAgentIds(cfg);
  if (knownAgentIds.length === 0) {
    return null;
  }

  const workspaceDir = normalizeOptionalString(ctx.workspaceDir);
  if (workspaceDir) {
    const currentPath = normalizeComparablePath(workspaceDir);
    const matches = knownAgentIds
      .map((agentId) => {
        const roots = uniqueStrings([
          (() => {
            try {
              return runtimeContext.runtime.agent.resolveAgentWorkspaceDir(cfg, agentId);
            } catch {
              return undefined;
            }
          })(),
          (() => {
            try {
              return runtimeContext.runtime.agent.resolveAgentDir(cfg, agentId);
            } catch {
              return undefined;
            }
          })()
        ]).map((path) => normalizeComparablePath(path));
        const matchedRoot = roots
          .filter((root) => pathMatchesRoot(currentPath, root))
          .sort((left, right) => right.length - left.length)[0];
        return matchedRoot ? { agentId, matchedRoot } : null;
      })
      .filter((entry): entry is { agentId: string; matchedRoot: string } => Boolean(entry))
      .sort((left, right) => right.matchedRoot.length - left.matchedRoot.length);

    if (matches.length === 1) {
      return {
        agentId: matches[0].agentId,
        reason: `workspace '${workspaceDir}'`
      };
    }
    if (matches.length > 1 && matches[0].matchedRoot.length > matches[1].matchedRoot.length) {
      return {
        agentId: matches[0].agentId,
        reason: `workspace '${workspaceDir}'`
      };
    }
  }

  if (knownAgentIds.length === 1) {
    return {
      agentId: knownAgentIds[0],
      reason: "the only configured local OpenClaw agent"
    };
  }

  return null;
}

function deriveStableSlotForAgent(cfg: OpenClawConfig, openclawAgent: string): string {
  const usedSlots = new Set(listAgentsChatAccounts(cfg).map((account) => account.slot));
  const preferred = normalizeSlot(openclawAgent);
  if (!usedSlots.has(preferred)) {
    return preferred;
  }

  const channelBase = normalizeSlot(`${openclawAgent}-agentschat`);
  if (!usedSlots.has(channelBase)) {
    return channelBase;
  }

  let suffix = 2;
  while (usedSlots.has(`${channelBase}-${suffix}`)) {
    suffix += 1;
  }
  return `${channelBase}-${suffix}`;
}

function resolveConnectAgentId(
  runtimeContext: AgentsChatRuntimeContext,
  ctx: OpenClawPluginCliContext,
  cfg: OpenClawConfig,
  opts: ConnectAccountInput,
  launcherValues: Record<string, string> | null
): {
  agentId: string;
  inferred: boolean;
  reason?: string;
} {
  const explicitAgentId = normalizeOptionalString(opts.openclawAgent);
  if (explicitAgentId) {
    validateKnownOpenClawAgentId(cfg, explicitAgentId);
    return {
      agentId: explicitAgentId,
      inferred: false
    };
  }

  const explicitSlot = normalizeOptionalString(opts.slot) ?? normalizeOptionalString(launcherValues?.slot);
  if (explicitSlot) {
    const existingAccount = findAgentsChatAccount(cfg, normalizeSlot(explicitSlot));
    if (existingAccount?.openclawAgent) {
      return {
        agentId: existingAccount.openclawAgent,
        inferred: true,
        reason: `existing slot '${existingAccount.slot}'`
      };
    }
  }

  const inferred = inferOpenClawAgentIdFromWorkspace(runtimeContext, ctx, cfg);
  if (inferred) {
    return {
      agentId: inferred.agentId,
      inferred: true,
      reason: inferred.reason
    };
  }

  throw new Error(
    "Could not infer the local OpenClaw agent for this Agents Chat connect. Run the command from that agent's workspace, or pass --agent <local-agent-id> once."
  );
}

function resolveSlotForAgent(
  cfg: OpenClawConfig,
  openclawAgent: string,
  requestedSlot?: string,
  options?: {
    requireExisting?: boolean;
  }
): string {
  const existingSlots = uniqueStrings(
    listAgentsChatAccounts(cfg)
      .filter((account) => account.openclawAgent === openclawAgent)
      .map((account) => account.slot)
  );
  const normalizedRequestedSlot = normalizeOptionalString(requestedSlot)
    ? normalizeSlot(requestedSlot!)
    : undefined;

  if (existingSlots.length > 1) {
    if (normalizedRequestedSlot && existingSlots.includes(normalizedRequestedSlot)) {
      return normalizedRequestedSlot;
    }
    throw new Error(
      `Local OpenClaw agent '${openclawAgent}' is already linked to multiple Agents Chat slots (${existingSlots.map((slot) => `'${slot}'`).join(", ")}). Pass --slot to choose the existing slot you want to keep using.`
    );
  }

  if (normalizedRequestedSlot) {
    if (existingSlots.length === 1 && existingSlots[0] !== normalizedRequestedSlot) {
      throw new Error(
        `Local OpenClaw agent '${openclawAgent}' is already linked to slot '${existingSlots[0]}'. Reuse that slot instead of creating a second one.`
      );
    }
    const existingAccount = findAgentsChatAccount(cfg, normalizedRequestedSlot);
    if (existingAccount && existingAccount.openclawAgent !== openclawAgent) {
      throw new Error(
        `Agents Chat slot '${normalizedRequestedSlot}' is already linked to local OpenClaw agent '${existingAccount.openclawAgent}'.`
      );
    }
    return normalizedRequestedSlot;
  }

  if (existingSlots.length === 1) {
    return existingSlots[0];
  }
  if (options?.requireExisting) {
    throw new Error(
      `Could not find an existing Agents Chat slot for local OpenClaw agent '${openclawAgent}'. Connect once first, or pass --slot explicitly if you are recovering an old slot.`
    );
  }
  return deriveStableSlotForAgent(cfg, openclawAgent);
}

function buildBaseAccount(input: ConnectAccountInput): AgentsChatAccountConfig {
  const openclawAgent = normalizeOptionalString(input.openclawAgent);
  const slot = normalizeOptionalString(input.slot);
  if (!openclawAgent) {
    throw new Error("openclawAgent is required before building the account config.");
  }
  if (!slot) {
    throw new Error("slot is required before building the account config.");
  }
  return {
    openclawAgent,
    slot: normalizeSlot(slot),
    mode: input.mode ?? "public",
    launcherUrl: input.launcherUrl?.trim() || undefined,
    serverBaseUrl: input.serverBaseUrl?.trim() || DEFAULT_SERVER_BASE_URL,
    handle: input.handle?.trim() || undefined,
    displayName: input.displayName?.trim() || undefined,
    bio: input.bio?.trim() || undefined,
    profileTags: input.profileTags?.map((entry) => entry.trim()).filter((entry) => entry.length > 0),
    avatarEmoji: input.avatarEmoji?.trim() || undefined,
    avatarFilePath: input.avatarFilePath?.trim() || undefined,
    autoStart: input.autoStart ?? true,
    transport: input.transport ?? DEFAULT_TRANSPORT,
    webhookBaseUrl: input.webhookBaseUrl?.trim() || undefined
  };
}

async function writeConfig(runtimeContext: AgentsChatRuntimeContext, cfg: OpenClawConfig): Promise<void> {
  await runtimeContext.runtime.config.writeConfigFile(cfg);
}

function effectiveActivityLevel(policy: {
  activityLevel?: AgentsChatActivityLevel;
  allowProactiveInteractions?: boolean;
} | null | undefined): AgentsChatActivityLevel {
  if (!policy || policy.allowProactiveInteractions === false) {
    return "low";
  }
  return policy.activityLevel ?? "normal";
}

async function refreshPolicyIfPossible(
  runtimeContext: AgentsChatRuntimeContext,
  slot: string
): Promise<{
  refreshed: boolean;
  policy?: Record<string, unknown>;
  error?: string;
}> {
  const state = loadSlotState(slot, runtimeContext.stateStore);
  if (!isResumeCapableState(state)) {
    return { refreshed: false };
  }
  try {
    const policy = await readSafetyPolicy(state.serverBaseUrl!, state.accessToken!);
    state.safetyPolicy = policy;
    state.safetyPolicyFetchedAtUnixMs = Date.now();
    state.lastPolicySyncAt = nowIso();
    state.lastError = null;
    saveSlotState(slot, state, runtimeContext.stateStore);
    return {
      refreshed: true,
      policy
    };
  } catch (error) {
    return {
      refreshed: false,
      error: error instanceof Error ? error.message : String(error)
    };
  }
}

function buildManagerDecision(account: AgentsChatAccountConfig, slot: string, runtimeContext: AgentsChatRuntimeContext) {
  const persisted = loadSlotState(slot, runtimeContext.stateStore);
  const configuredState = describeAgentsChatAccountConfiguredState(account, persisted);
  if (account.autoStart === false) {
    return {
      shouldStart: false,
      reason: "autoStart=false"
    };
  }
  if (!configuredState.configured) {
    return {
      shouldStart: false,
      reason: configuredState.reason
    };
  }
  if (persisted.conflictState) {
    return {
      shouldStart: false,
      reason: `blocked by conflict: ${persisted.conflictState}`
    };
  }
  return {
    shouldStart: true,
    reason: configuredState.resumeCapable
      ? "configured and resume-capable"
      : "configured and bootstrap-capable"
  };
}

async function handleConnect(
  runtimeContext: AgentsChatRuntimeContext,
  opts: ConnectAccountInput,
  ctx: OpenClawPluginCliContext
): Promise<void> {
  const cfg = runtimeContext.runtime.config.loadConfig();
  const launcherValues = opts.launcherUrl ? parseLauncherUrl(opts.launcherUrl) : null;
  if (launcherValues?.mode === "claim") {
    const requestedClaimSlot = normalizeOptionalString(opts.slot) ?? normalizeOptionalString(launcherValues.slot);
    const slot = requestedClaimSlot
      ? normalizeSlot(requestedClaimSlot)
      : (() => {
        const resolvedAgent = resolveConnectAgentId(runtimeContext, ctx, cfg, opts, launcherValues);
        if (resolvedAgent.inferred && resolvedAgent.reason) {
          ctx.logger.info(
            `Agents Chat inferred local OpenClaw agent '${resolvedAgent.agentId}' from ${resolvedAgent.reason}.`
          );
        }
        return resolveSlotForAgent(cfg, resolvedAgent.agentId, undefined, {
          requireExisting: true
        });
      })();
    migrateLegacyStateIfNeeded(slot, runtimeContext.stateStore);
    const state = loadSlotState(slot, runtimeContext.stateStore);
    const result = await confirmClaimLauncher(state, opts.launcherUrl!);
    console.log(
      asJson({
        status: result.status ?? "claim_confirmed",
        slot,
        agentId: state.agentId,
        result
      })
    );
    return;
  }

  const resolvedAgent = resolveConnectAgentId(runtimeContext, ctx, cfg, opts, launcherValues);
  if (resolvedAgent.inferred && resolvedAgent.reason) {
    ctx.logger.info(
      `Agents Chat inferred local OpenClaw agent '${resolvedAgent.agentId}' from ${resolvedAgent.reason}.`
    );
  }
  let account = buildBaseAccount({
    ...opts,
    openclawAgent: resolvedAgent.agentId,
    mode: opts.mode ?? (launcherValues?.mode ? normalizeMode(launcherValues.mode) : "public"),
    serverBaseUrl: opts.serverBaseUrl ?? launcherValues?.serverBaseUrl ?? DEFAULT_SERVER_BASE_URL,
    slot: resolveSlotForAgent(
      cfg,
      resolvedAgent.agentId,
      normalizeOptionalString(opts.slot) ?? normalizeOptionalString(launcherValues?.slot)
    ),
    handle: opts.handle ?? launcherValues?.handle,
    displayName: opts.displayName ?? launcherValues?.displayName
  });
  account = mergeLauncherIntoAccount(account, opts.launcherUrl);

  migrateLegacyStateIfNeeded(account.slot, runtimeContext.stateStore);
  const priorState = loadSlotState(account.slot, runtimeContext.stateStore);
  const isFirstPublicBootstrap = account.mode === "public"
    && !isResumeCapableState(priorState)
    && !priorState.agentId;
  if (isFirstPublicBootstrap && (!account.handle || !account.displayName)) {
    const draftedProfile = await draftInitialPublicProfile(runtimeContext, account);
    account = {
      ...account,
      handle: account.handle ?? draftedProfile.handle,
      displayName: account.displayName ?? draftedProfile.displayName
    };
    ctx.logger.info(
      `Agents Chat slot '${account.slot}' drafted initial public profile as @${account.handle} (${account.displayName}).`
    );
  }

  const nextCfg = upsertAgentsChatAccount(runtimeContext.runtime.config.loadConfig(), account);
  await writeConfig(runtimeContext, nextCfg);

  clearWorkerConflict(account.slot);
  const nextState = await connectAccount(account, loadSlotState(account.slot, runtimeContext.stateStore), ctx.logger);
  saveSlotState(account.slot, nextState, runtimeContext.stateStore);
  const persistedAccount = {
    ...account,
    handle: nextState.agentHandle ?? account.handle,
    displayName: nextState.displayName ?? account.displayName,
    bio: nextState.bio ?? account.bio,
    profileTags: nextState.profileTags ?? account.profileTags,
    avatarEmoji: nextState.avatarEmoji ?? account.avatarEmoji
  };
  const syncedCfg = upsertAgentsChatAccount(runtimeContext.runtime.config.loadConfig(), persistedAccount);
  await writeConfig(runtimeContext, syncedCfg);
  if (account.autoStart !== false) {
    await reconcileManagedAccounts(runtimeContext, ctx.logger);
  }

  console.log(
    asJson({
      status: "connected",
      slot: account.slot,
      openclawAgent: account.openclawAgent,
      agentId: nextState.agentId,
      mode: account.mode,
      serverBaseUrl: nextState.serverBaseUrl,
      handle: nextState.agentHandle ?? persistedAccount.handle ?? null,
      displayName: nextState.displayName ?? persistedAccount.displayName ?? null,
      autoStart: account.autoStart ?? true,
      resumeCapable: isResumeCapableState(nextState),
      pluginStateRoot: runtimeContext.pluginStateRoot
    })
  );
}

async function handleStatus(runtimeContext: AgentsChatRuntimeContext): Promise<void> {
  const cfg = runtimeContext.runtime.config.loadConfig();
  const accounts = listAgentsChatAccounts(cfg);
  const enrichedAccounts = [];

  for (const account of accounts) {
    migrateLegacyStateIfNeeded(account.slot, runtimeContext.stateStore);
    const persisted = loadSlotState(account.slot, runtimeContext.stateStore);
    const configuredState = describeAgentsChatAccountConfiguredState(account, persisted);
    const runtimeState = getWorkerSnapshot(account.slot);
    const refresh = await refreshPolicyIfPossible(runtimeContext, account.slot);
    const latestPersisted = loadSlotState(account.slot, runtimeContext.stateStore);
    const policy = latestPersisted.safetyPolicy;

    enrichedAccounts.push({
      slot: account.slot,
      config: {
        openclawAgent: account.openclawAgent,
        mode: account.mode,
        autoStart: account.autoStart ?? true,
        transport: account.transport ?? DEFAULT_TRANSPORT,
        serverBaseUrl: account.serverBaseUrl ?? null,
        launcherUrlPresent: Boolean(account.launcherUrl),
        webhookBaseUrl: account.webhookBaseUrl ?? null,
        configured: configuredState.configured,
        configuredReason: configuredState.reason,
        resumeCapable: configuredState.resumeCapable,
        bootstrapCapable: isBootstrapCapableAccount(account)
      },
      persistedState: {
        path: resolveSlotStateFilePath(account.slot, runtimeContext.stateStore),
        agentId: latestPersisted.agentId ?? null,
        handle: latestPersisted.agentHandle ?? account.handle ?? null,
        displayName: latestPersisted.displayName ?? account.displayName ?? null,
        serverBaseUrl: latestPersisted.serverBaseUrl ?? account.serverBaseUrl ?? null,
        lastConnectedAt: latestPersisted.lastConnectedAt ?? null,
        lastInboundAt: latestPersisted.lastInboundAt ?? null,
        lastOutboundAt: latestPersisted.lastOutboundAt ?? null,
        lastPolicySyncAt: latestPersisted.lastPolicySyncAt ?? null,
        lastDiscoveryAt: latestPersisted.lastDiscoveryAt ?? null,
        lastProactiveActionAt: latestPersisted.lastProactiveActionAt ?? null,
        lastProactiveActionType: latestPersisted.lastProactiveActionType ?? null,
        degradedReason: latestPersisted.degradedReason ?? null,
        conflictState: latestPersisted.conflictState ?? null,
        lastError: latestPersisted.lastError ?? null
      },
      runtime: {
        running: runtimeState.running,
        connected: runtimeState.connected,
        reconnectAttempts: runtimeState.reconnectAttempts,
        lastConnectedAt: runtimeState.lastConnectedAt ?? toUnixMs(latestPersisted.lastConnectedAt),
        lastInboundAt: runtimeState.lastInboundAt ?? toUnixMs(latestPersisted.lastInboundAt),
        lastOutboundAt: runtimeState.lastOutboundAt ?? toUnixMs(latestPersisted.lastOutboundAt),
        lastPolicySyncAt: runtimeState.lastPolicySyncAt ?? toUnixMs(latestPersisted.lastPolicySyncAt),
        lastDiscoveryAt: runtimeState.lastDiscoveryAt ?? toUnixMs(latestPersisted.lastDiscoveryAt),
        lastProactiveActionAt: runtimeState.lastProactiveActionAt ?? toUnixMs(latestPersisted.lastProactiveActionAt),
        lastProactiveActionType: runtimeState.lastProactiveActionType ?? latestPersisted.lastProactiveActionType ?? null,
        healthState: runtimeState.healthState,
        degradedReason: runtimeState.degradedReason ?? latestPersisted.degradedReason ?? null,
        conflictState: runtimeState.conflictState ?? latestPersisted.conflictState ?? null,
        lastError: runtimeState.lastError ?? latestPersisted.lastError ?? null
      },
      remotePolicy: {
        snapshot: policy ?? null,
        fetchedAt: latestPersisted.lastPolicySyncAt
          ?? (typeof latestPersisted.safetyPolicyFetchedAtUnixMs === "number"
            ? new Date(latestPersisted.safetyPolicyFetchedAtUnixMs).toISOString()
            : null),
        effectiveActivityLevel: effectiveActivityLevel(policy),
        refreshedNow: refresh.refreshed,
        refreshError: refresh.error ?? null
      },
      legacy: {
        sources: inspectLegacyStateSources(account.slot).map((source) => ({
          kind: source.kind,
          path: source.path
        }))
      },
      manager: buildManagerDecision(account, account.slot, runtimeContext)
    });
  }

  console.log(asJson({
    pluginRuntimeVersion: runtimeContext.runtime.version,
    pluginStateRoot: runtimeContext.pluginStateRoot,
    defaultPluginStateRoot: resolveDefaultPluginStateRoot(),
    accounts: enrichedAccounts
  }));
}

async function handleDisconnect(
  runtimeContext: AgentsChatRuntimeContext,
  slot: string,
  removeConfig: boolean
): Promise<void> {
  const normalizedSlot = normalizeSlot(slot);
  await disconnectAccount(normalizedSlot, runtimeContext);
  if (removeConfig) {
    const nextCfg = removeAgentsChatAccount(runtimeContext.runtime.config.loadConfig(), normalizedSlot);
    await writeConfig(runtimeContext, nextCfg);
  }
  console.log(
    asJson({
      status: "disconnected",
      slot: normalizedSlot,
      removeConfig
    })
  );
}

async function runDoctorCheck(
  runtimeContext: AgentsChatRuntimeContext,
  account: AgentsChatAccountConfig
): Promise<Record<string, unknown>> {
  migrateLegacyStateIfNeeded(account.slot, runtimeContext.stateStore);
  const persisted = loadSlotState(account.slot, runtimeContext.stateStore);
  const configuredState = describeAgentsChatAccountConfiguredState(account, persisted);
  const runtimeState = getWorkerSnapshot(account.slot);
  const checks: Array<Record<string, unknown>> = [];

  checks.push({
    name: "state_root",
    ok: runtimeContext.pluginStateRoot === resolveDefaultPluginStateRoot(),
    pluginStateRoot: runtimeContext.pluginStateRoot,
    defaultPluginStateRoot: resolveDefaultPluginStateRoot()
  });
  checks.push({
    name: "configured",
    ok: configuredState.configured,
    configured: configuredState.configured,
    configuredReason: configuredState.reason,
    resumeCapable: configuredState.resumeCapable,
    bootstrapCapable: isBootstrapCapableAccount(account)
  });
  checks.push({
    name: "manager_decision",
    ...buildManagerDecision(account, account.slot, runtimeContext)
  });

  const legacySources = inspectLegacyStateSources(account.slot).map((source) => ({
    kind: source.kind,
    path: source.path
  }));
  checks.push({
    name: "legacy_state_sources",
    ok: true,
    sourceCount: legacySources.length,
    note: legacySources.length > 0
      ? "Legacy bridge state still exists. Make sure an old bridge is not also managing this agentId."
      : "No legacy state sources found.",
    sources: legacySources
  });

  checks.push({
    name: "runtime_snapshot",
    ok: true,
    running: runtimeState.running,
    connected: runtimeState.connected,
    reconnectAttempts: runtimeState.reconnectAttempts,
    conflictState: runtimeState.conflictState ?? persisted.conflictState ?? null,
    degradedReason: runtimeState.degradedReason ?? persisted.degradedReason ?? null,
    lastError: runtimeState.lastError ?? persisted.lastError ?? null
  });

  if (isResumeCapableState(persisted)) {
    try {
      const policy = await readSafetyPolicy(persisted.serverBaseUrl!, persisted.accessToken!);
      checks.push({
        name: "self_safety_policy",
        ok: true,
        policy,
        effectiveActivityLevel: effectiveActivityLevel(policy)
      });
    } catch (error) {
      checks.push({
        name: "self_safety_policy",
        ok: false,
        error: error instanceof Error ? error.message : String(error)
      });
    }

    try {
      await pollDeliveries(persisted.serverBaseUrl!, persisted.accessToken!, 0);
      checks.push({
        name: "polling",
        ok: true
      });
    } catch (error) {
      checks.push({
        name: "polling",
        ok: false,
        error: error instanceof Error ? error.message : String(error)
      });
    }
  } else {
    checks.push({
      name: "resume_token",
      ok: false,
      error: "Persisted state is not resume-capable yet."
    });
  }

  try {
    const debates = await readDebates(
      persisted.serverBaseUrl ?? account.serverBaseUrl ?? DEFAULT_SERVER_BASE_URL,
      3
    );
    checks.push({
      name: "public_debates_index",
      ok: true,
      sessionCount: Array.isArray(debates.sessions) ? debates.sessions.length : 0
    });
  } catch (error) {
    checks.push({
      name: "public_debates_index",
      ok: false,
      error: error instanceof Error ? error.message : String(error)
    });
  }

  return {
    slot: account.slot,
    openclawAgent: account.openclawAgent,
    statePath: resolveSlotStateFilePath(account.slot, runtimeContext.stateStore),
    persistedAgentId: persisted.agentId ?? null,
    checks
  };
}

async function handleDoctor(
  runtimeContext: AgentsChatRuntimeContext,
  slot: string | undefined
): Promise<void> {
  const cfg = runtimeContext.runtime.config.loadConfig();
  const accounts = slot
    ? [findAgentsChatAccount(cfg, normalizeSlot(slot))].filter(Boolean) as AgentsChatAccountConfig[]
    : listAgentsChatAccounts(cfg);

  const checks = [];
  for (const account of accounts) {
    checks.push(await runDoctorCheck(runtimeContext, account));
  }

  console.log(
    asJson({
      pluginRuntimeVersion: runtimeContext.runtime.version,
      pluginStateRoot: runtimeContext.pluginStateRoot,
      checks
    })
  );
}

export function registerAgentsChatCli(
  runtimeContext: AgentsChatRuntimeContext,
  ctx: OpenClawPluginCliContext
): void {
  const agentsChat = ctx.program.command("agentschatapp").description("Manage agentschatapp plugin accounts");

  agentsChat
    .command("connect")
    .description("Connect or update an agentschatapp account")
    .option("--launcher-url <url>", "Agents Chat public, bound, or claim launcher")
    .option("--agent <id>", "Local OpenClaw agent id; optional when the plugin can infer the current agent")
    .option("--slot <slot>", "Advanced override for the local Agents Chat slot; normally auto-derived from the local agent")
    .option("--mode <mode>", "public or bound")
    .option("--server-base-url <url>", "Agents Chat server base URL", DEFAULT_SERVER_BASE_URL)
    .option("--handle <handle>", "Optional public Agents Chat handle override")
    .option("--display-name <name>", "Optional public display name override")
    .option("--bio <bio>", "Preferred public bio")
    .option("--profile-tag <tag>", "Profile tag (repeatable)", collectStringOption, [])
    .option("--avatar-emoji <emoji>", "Emoji avatar to sync")
    .option("--avatar-file <path>", "Local image file to upload as the avatar")
    .option("--transport <transport>", "polling or hybrid", DEFAULT_TRANSPORT)
    .option("--webhook-base-url <url>", "Optional public webhook base URL for hybrid transport")
    .option("--auto-start [enabled]", "Keep this account managed by the background plugin", boolOption, true)
    .action(async (options: Record<string, unknown>) => {
      await handleConnect(
        runtimeContext,
        {
          launcherUrl: typeof options.launcherUrl === "string" ? options.launcherUrl : undefined,
          openclawAgent: typeof options.agent === "string" ? options.agent : undefined,
          slot: typeof options.slot === "string" ? options.slot : undefined,
          mode: typeof options.mode === "string" ? normalizeMode(options.mode) : undefined,
          serverBaseUrl: typeof options.serverBaseUrl === "string" ? options.serverBaseUrl : undefined,
          handle: typeof options.handle === "string" ? options.handle : undefined,
          displayName: typeof options.displayName === "string" ? options.displayName : undefined,
          bio: typeof options.bio === "string" ? options.bio : undefined,
          profileTags: Array.isArray(options.profileTag)
            ? options.profileTag.filter((entry): entry is string => typeof entry === "string")
            : undefined,
          avatarEmoji: typeof options.avatarEmoji === "string" ? options.avatarEmoji : undefined,
          avatarFilePath: typeof options.avatarFile === "string" ? options.avatarFile : undefined,
          transport: options.transport === "hybrid" ? "hybrid" : "polling",
          webhookBaseUrl: typeof options.webhookBaseUrl === "string" ? options.webhookBaseUrl : undefined,
          autoStart: typeof options.autoStart === "boolean" ? options.autoStart : true
        },
        ctx
      );
    });

  agentsChat
    .command("status")
    .description("Show configured agentschatapp accounts")
    .action(async () => {
      await handleStatus(runtimeContext);
    });

  agentsChat
    .command("disconnect")
    .description("Stop one agentschatapp slot and optionally remove it from config")
    .requiredOption("--slot <slot>", "Agents Chat slot to disconnect")
    .option("--remove-config", "Remove the slot from OpenClaw config too", false)
    .action(async (options: Record<string, unknown>) => {
      await handleDisconnect(runtimeContext, String(options.slot), Boolean(options.removeConfig));
    });

  agentsChat
    .command("doctor")
    .description("Run a richer agentschatapp plugin health check")
    .option("--slot <slot>", "Check only one slot")
    .action(async (options: Record<string, unknown>) => {
      await handleDoctor(runtimeContext, typeof options.slot === "string" ? options.slot : undefined);
    });
}
