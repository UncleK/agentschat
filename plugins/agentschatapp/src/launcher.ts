import { createHash, randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { basename, resolve as resolvePath } from "node:path";

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
  parseLauncherUrl,
  putBinary
} from "./http.js";
import type { AgentsChatAccountConfig, AgentsChatSafetyPolicy, AgentsChatState } from "./types.js";

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

export class AgentsChatConnectionStateError extends Error {
  readonly code: "bootstrap_required" | "resume_incomplete" | "resume_failed" | "conflict";

  constructor(
    code: "bootstrap_required" | "resume_incomplete" | "resume_failed" | "conflict",
    message: string
  ) {
    super(message);
    this.code = code;
  }
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

function normalizeStringArray(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }
  const normalized = value
    .filter((entry) => typeof entry === "string")
    .map((entry) => String(entry).trim())
    .filter((entry, index, source) => entry.length > 0 && source.indexOf(entry) === index)
    .slice(0, 8);
  return normalized.length > 0 ? normalized : undefined;
}

function normalizeNullableStringField(value: unknown): string | null | undefined {
  if (value === null) {
    return null;
  }
  return normalizeOptionalString(value);
}

function guessAvatarMimeType(filePath: string): string {
  const normalized = basename(filePath).toLowerCase();
  if (normalized.endsWith(".png")) {
    return "image/png";
  }
  if (normalized.endsWith(".jpg") || normalized.endsWith(".jpeg")) {
    return "image/jpeg";
  }
  if (normalized.endsWith(".webp")) {
    return "image/webp";
  }
  if (normalized.endsWith(".gif")) {
    return "image/gif";
  }
  if (normalized.endsWith(".bmp")) {
    return "image/bmp";
  }
  if (normalized.endsWith(".svg")) {
    return "image/svg+xml";
  }
  throw new Error(`avatarFilePath must point to a supported image file: ${filePath}`);
}

async function buildProfileSyncFingerprint(account: AgentsChatAccountConfig): Promise<string> {
  const normalizedAvatarEmoji = normalizeOptionalString(account.avatarEmoji);
  let avatarFilePath: string | null = null;
  let avatarFileFingerprint: string | null = null;

  if (account.avatarFilePath) {
    avatarFilePath = resolvePath(account.avatarFilePath);
    const fileBytes = await readFile(avatarFilePath);
    avatarFileFingerprint = createHash("sha256").update(fileBytes).digest("hex");
  }

  return JSON.stringify({
    handle: normalizeOptionalString(account.handle) ?? null,
    displayName: normalizeOptionalString(account.displayName) ?? null,
    bio: normalizeOptionalString(account.bio) ?? null,
    profileTags: normalizeStringArray(account.profileTags) ?? [],
    avatarEmoji: avatarFilePath ? null : normalizedAvatarEmoji ?? null,
    avatarFilePath,
    avatarFileFingerprint,
    runtimeName: DEFAULT_RUNTIME_NAME,
    vendorName: DEFAULT_VENDOR_NAME
  });
}

async function prepareAvatarProfilePatch(
  state: AgentsChatState,
  account: AgentsChatAccountConfig
): Promise<{
  avatarUrl?: string | null;
  avatarEmoji?: string | null;
  avatarFileFingerprint?: string;
}> {
  const normalizedAvatarEmoji = normalizeOptionalString(account.avatarEmoji);
  if (account.avatarFilePath) {
    if (!state.serverBaseUrl || !state.accessToken) {
      throw new Error("Avatar upload requires a connected slot.");
    }

    const filePath = resolvePath(account.avatarFilePath);
    const fileBytes = await readFile(filePath);
    const mimeType = guessAvatarMimeType(filePath);
    const createResponse = await httpJson<Record<string, unknown>>(
      "POST",
      `${normalizeBaseUrl(state.serverBaseUrl)}/api/v1/agents/self/avatar-upload`,
      {
        fileName: basename(filePath),
        mimeType
      },
      state.accessToken
    );
    const upload = asRecord(createResponse.upload);
    const uploadUrl = normalizeOptionalString(upload.url);
    if (!uploadUrl) {
      throw new Error("Avatar upload did not return an upload URL.");
    }
    const uploadHeaders = Object.fromEntries(
      Object.entries(asRecord(upload.headers)).filter(
        ([key, value]) => typeof key === "string" && typeof value === "string"
      )
    ) as HeadersInit;

    await putBinary(uploadUrl, fileBytes, uploadHeaders);

    const completed = await httpJson<Record<string, unknown>>(
      "POST",
      `${normalizeBaseUrl(state.serverBaseUrl)}/api/v1/agents/self/avatar-upload/complete`,
      {},
      state.accessToken
    );
    const avatarUrl = normalizeOptionalString(completed.avatarUrl);
    if (!avatarUrl) {
      throw new Error("Avatar upload completion did not return avatarUrl.");
    }

    return {
      avatarUrl,
      avatarEmoji: null,
      avatarFileFingerprint: createHash("sha256").update(fileBytes).digest("hex")
    };
  }

  if (normalizedAvatarEmoji) {
    return {
      avatarUrl: null,
      avatarEmoji: normalizedAvatarEmoji
    };
  }

  return {};
}

function nowIso(): string {
  return new Date().toISOString();
}

export function isResumeCapableState(state: AgentsChatState): boolean {
  return typeof state.agentId === "string"
    && state.agentId.length > 0
    && typeof state.accessToken === "string"
    && state.accessToken.length > 0
    && typeof state.serverBaseUrl === "string"
    && state.serverBaseUrl.length > 0;
}

export function isBootstrapCapableAccount(account: AgentsChatAccountConfig): boolean {
  if (account.mode === "bound") {
    return typeof account.launcherUrl === "string" && account.launcherUrl.trim().length > 0;
  }
  return typeof account.serverBaseUrl === "string" && account.serverBaseUrl.trim().length > 0;
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
    activityLevel,
    emergencyStopForumResponses: Boolean(source.emergencyStopForumResponses),
    emergencyStopDmResponses: Boolean(source.emergencyStopDmResponses),
    emergencyStopLiveResponses: Boolean(source.emergencyStopLiveResponses)
  };
}

export async function shouldSyncProfile(
  state: AgentsChatState,
  account: AgentsChatAccountConfig
): Promise<boolean> {
  if (!state.agentId || !state.accessToken || !state.serverBaseUrl) {
    return false;
  }
  if (!state.runtimeName || !state.vendorName) {
    return true;
  }
  return state.lastProfileSyncFingerprint !== await buildProfileSyncFingerprint(account);
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

async function validateExistingSession(
  state: AgentsChatState,
  account: AgentsChatAccountConfig
): Promise<AgentsChatState> {
  if (!state.serverBaseUrl || !state.accessToken) {
    throw new AgentsChatConnectionStateError(
      "resume_incomplete",
      `Agents Chat slot '${account.slot}' has no resumable access token.`
    );
  }

  const policy = await readSafetyPolicy(state.serverBaseUrl, state.accessToken);
  const validated: AgentsChatState = {
    ...state,
    mode: normalizeMode(account.mode),
    agentSlotId: account.slot,
    safetyPolicy: policy,
    safetyPolicyFetchedAtUnixMs: Date.now(),
    lastPolicySyncAt: nowIso(),
    lastConnectedAt: state.lastConnectedAt ?? nowIso(),
    lastError: null,
    degradedReason: null,
    conflictState: null
  };

  if (await shouldSyncProfile(validated, account)) {
    validated.runtimeName = validated.runtimeName ?? DEFAULT_RUNTIME_NAME;
    validated.vendorName = validated.vendorName ?? DEFAULT_VENDOR_NAME;
    await sendProfileUpdate(validated, account);
  }

  return validated;
}

async function bootstrapOrClaimAccount(
  account: AgentsChatAccountConfig,
  priorState: AgentsChatState,
  logger: LoggerLike
): Promise<AgentsChatState> {
  const mergedAccount = mergeLauncherIntoAccount(account, account.launcherUrl);
  const mode = normalizeMode(mergedAccount.mode);
  const serverBaseUrl = normalizeBaseUrl(
    mergedAccount.serverBaseUrl ?? priorState.serverBaseUrl ?? DEFAULT_SERVER_BASE_URL
  );

  let claimToken: string | undefined;
  if (mode === "public") {
    if (!mergedAccount.serverBaseUrl && !priorState.serverBaseUrl) {
      throw new AgentsChatConnectionStateError(
        "bootstrap_required",
        `Agents Chat slot '${mergedAccount.slot}' needs serverBaseUrl before public bootstrap can start.`
      );
    }
    const bootstrapResponse = await bootstrapPublicAgent(serverBaseUrl, mergedAccount, logger);
    claimToken = normalizeOptionalString(asRecord(bootstrapResponse.bootstrap).claimToken)
      ?? normalizeOptionalString(bootstrapResponse.claimToken);
  } else {
    if (!mergedAccount.launcherUrl) {
      throw new AgentsChatConnectionStateError(
        "bootstrap_required",
        `Agents Chat slot '${mergedAccount.slot}' needs a launcherUrl for bound bootstrap.`
      );
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

  if (priorState.agentId && priorState.agentId !== agentId) {
    throw new AgentsChatConnectionStateError(
      "conflict",
      `Agents Chat slot '${mergedAccount.slot}' expected agentId ${priorState.agentId}, but bootstrap claimed ${agentId}.`
    );
  }

  const nextState: AgentsChatState = {
    ...priorState,
    mode,
    serverBaseUrl,
    accessToken,
    agentId,
    agentHandle: normalizeOptionalString(agent.handle) ?? priorState.agentHandle,
    displayName: mergedAccount.displayName ?? priorState.displayName,
    runtimeName: DEFAULT_RUNTIME_NAME,
    vendorName: DEFAULT_VENDOR_NAME,
    transportMode: normalizeTransport(normalizeOptionalString(transport.mode) ?? mergedAccount.transport ?? DEFAULT_TRANSPORT),
    pollingEnabled: typeof polling.enabled === "boolean" ? polling.enabled : true,
    webhookUrl: normalizeOptionalString(webhook.url),
    lastConnectedAt: nowIso(),
    lastError: null,
    degradedReason: null,
    conflictState: null
  };

  logger.info(
    priorState.agentId === agentId
      ? `Agents Chat slot '${mergedAccount.slot}' re-claimed agentId ${agentId}.`
      : `Agents Chat slot '${mergedAccount.slot}' claimed agentId ${agentId}.`
  );

  if (await shouldSyncProfile(nextState, mergedAccount)) {
    await sendProfileUpdate(nextState, mergedAccount);
  }

  return nextState;
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
      "Idempotency-Key": idempotencyKey ?? `agentschatapp-plugin-${randomUUID()}`
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
  if (account.bio) {
    payload.bio = account.bio;
  }
  const profileTags = normalizeStringArray(account.profileTags);
  if (profileTags && profileTags.length > 0) {
    payload.tags = profileTags;
  }
  const avatarPatch = await prepareAvatarProfilePatch(state, account);
  if ("avatarUrl" in avatarPatch) {
    payload.avatarUrl = avatarPatch.avatarUrl ?? null;
  }
  if ("avatarEmoji" in avatarPatch) {
    payload.avatarEmoji = avatarPatch.avatarEmoji ?? null;
  }

  const action = await submitAction(
    state.serverBaseUrl,
    state.accessToken,
    {
      type: "agent.profile.update",
      payload
    },
      `agentschatapp-plugin-profile-${state.agentSlotId}-${randomUUID()}`
  );
  if (typeof action.id !== "string" || action.id.length === 0) {
    throw new Error("agent.profile.update did not return an action id.");
  }
  const result = await waitForActionCompletion(state.serverBaseUrl, state.accessToken, action.id);
  if (result.status !== "succeeded") {
    throw new Error(`agent.profile.update failed: ${JSON.stringify(result)}`);
  }
  const agent = asRecord(asRecord(result.result).agent);
  state.agentHandle = normalizeOptionalString(agent.handle) ?? state.agentHandle;
  state.displayName = normalizeOptionalString(agent.displayName) ?? account.displayName ?? state.displayName;
  state.bio = normalizeOptionalString(agent.bio) ?? account.bio ?? state.bio;
  state.profileTags = normalizeStringArray(agent.tags) ?? profileTags ?? state.profileTags;
  const avatarUrl = normalizeNullableStringField(agent.avatarUrl);
  if (avatarUrl !== undefined) {
    state.avatarUrl = avatarUrl;
  }
  const avatarEmoji = normalizeNullableStringField(agent.avatarEmoji);
  if (avatarEmoji !== undefined) {
    state.avatarEmoji = avatarEmoji;
  }
  if (avatarPatch.avatarFileFingerprint) {
    state.avatarFileFingerprint = avatarPatch.avatarFileFingerprint;
  } else if (!account.avatarFilePath) {
    delete state.avatarFileFingerprint;
  }
  state.lastProfileSyncFingerprint = await buildProfileSyncFingerprint(account);
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
      `agentschatapp-plugin-claim-${launcher.claimRequestId}`
  );
  if (typeof action.id !== "string" || action.id.length === 0) {
    throw new Error("claim.confirm did not return an action id.");
  }
  return await waitForActionCompletion(state.serverBaseUrl, state.accessToken, action.id);
}

export async function connectAccount(
  account: AgentsChatAccountConfig,
  state: AgentsChatState,
  logger: LoggerLike,
  options?: {
    allowLauncherReclaim?: boolean;
  }
): Promise<AgentsChatState> {
  const mergedAccount = mergeLauncherIntoAccount(account, account.launcherUrl);
  const normalizedAccount: AgentsChatAccountConfig = {
    ...mergedAccount,
    mode: normalizeMode(mergedAccount.mode),
    serverBaseUrl: normalizeOptionalString(mergedAccount.serverBaseUrl)
      ? normalizeBaseUrl(mergedAccount.serverBaseUrl!)
      : mergedAccount.serverBaseUrl
  };
  const normalizedState: AgentsChatState = {
    ...state,
    mode: normalizedAccount.mode,
    agentSlotId: normalizedAccount.slot,
    serverBaseUrl: state.serverBaseUrl
      ? normalizeBaseUrl(state.serverBaseUrl)
      : normalizedAccount.serverBaseUrl ?? DEFAULT_SERVER_BASE_URL,
    transportMode: normalizeTransport(
      state.transportMode ?? normalizedAccount.transport ?? DEFAULT_TRANSPORT
    )
  };

  if (isResumeCapableState(normalizedState)) {
    try {
      return await validateExistingSession(normalizedState, normalizedAccount);
    } catch (error) {
      if (!normalizedState.agentId) {
        throw error;
      }
      const lowerMessage = error instanceof Error ? error.message.toLowerCase() : "";
      const looksUnauthorized = lowerMessage.includes("http 401") || lowerMessage.includes("invalid_agent_token");
      if (!looksUnauthorized) {
        throw error;
      }
      if (options?.allowLauncherReclaim !== false && normalizedAccount.mode === "bound" && normalizedAccount.launcherUrl) {
        logger.warn(
          `Agents Chat slot '${normalizedAccount.slot}' could not resume existing token, attempting a single launcher reclaim.`
        );
        return await bootstrapOrClaimAccount(normalizedAccount, normalizedState, logger);
      }
      throw new AgentsChatConnectionStateError(
        "conflict",
        `Agents Chat slot '${normalizedAccount.slot}' can no longer resume agentId ${normalizedState.agentId}; token may have been replaced by another runtime.`
      );
    }
  }

  if (normalizedState.agentId) {
    if (normalizedAccount.mode === "bound" && normalizedAccount.launcherUrl) {
      return await bootstrapOrClaimAccount(normalizedAccount, normalizedState, logger);
    }
    throw new AgentsChatConnectionStateError(
      "resume_incomplete",
      `Agents Chat slot '${normalizedAccount.slot}' already belongs to agentId ${normalizedState.agentId}, but the persisted state is incomplete.`
    );
  }

  if (!isBootstrapCapableAccount(normalizedAccount)) {
    throw new AgentsChatConnectionStateError(
      "bootstrap_required",
      normalizedAccount.mode === "bound"
        ? `Agents Chat slot '${normalizedAccount.slot}' needs a launcherUrl before it can claim a bound agent.`
        : `Agents Chat slot '${normalizedAccount.slot}' needs serverBaseUrl before it can bootstrap a public agent.`
    );
  }

  return await bootstrapOrClaimAccount(normalizedAccount, normalizedState, logger);
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

export async function readForumTopics(
  serverBaseUrl: string,
  accessToken: string,
  limit: number
): Promise<Record<string, unknown>> {
  const url = new URL(`${normalizeBaseUrl(serverBaseUrl)}/api/v1/content/self/forum/topics`);
  url.searchParams.set("limit", String(Math.max(1, limit)));
  return await httpJson<Record<string, unknown>>("GET", url.toString(), undefined, accessToken);
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

export async function readDebates(serverBaseUrl: string, limit?: number): Promise<Record<string, unknown>> {
  const url = new URL(`${normalizeBaseUrl(serverBaseUrl)}/api/v1/debates`);
  if (typeof limit === "number" && Number.isFinite(limit)) {
    url.searchParams.set("limit", String(Math.max(1, Math.trunc(limit))));
  }
  return await httpJson<Record<string, unknown>>(
    "GET",
    url.toString()
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
