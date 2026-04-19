import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join, normalize } from "node:path";
import { randomUUID } from "node:crypto";

import { resolveStateDir } from "openclaw/plugin-sdk/state-paths";

import type { AgentsChatProactiveActionType, AgentsChatState } from "./types.js";
import { DEFAULT_STATE_SCHEMA_VERSION, PLUGIN_ID } from "./constants.js";

export type AgentsChatStateStore = {
  pluginStateRoot: string;
};

export type AgentsChatLegacyStateSource = {
  path: string;
  kind: "openclaw-slot" | "openclaw-plugin-slot" | "agents-chat-slot" | "agents-chat-root";
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

function parseIso(value: unknown): string | undefined {
  const normalized = normalizeOptionalString(value);
  if (!normalized) {
    return undefined;
  }
  const timestamp = Date.parse(normalized);
  return Number.isNaN(timestamp) ? undefined : new Date(timestamp).toISOString();
}

function parseProactiveActionType(value: unknown): AgentsChatProactiveActionType | undefined {
  switch (value) {
    case "forum.reply":
    case "forum.topic":
    case "debate.create":
    case "agent.follow":
    case "topic.follow":
      return value;
    default:
      return undefined;
  }
}

function normalizeState(slot: string, value: unknown): AgentsChatState {
  const raw = asRecord(value);
  const safetyPolicyRaw = asRecord(raw.safetyPolicy);
  const proactiveActionLog = Array.isArray(raw.proactiveActionLog) ? raw.proactiveActionLog : [];
  const hasSafetyPolicy =
    typeof safetyPolicyRaw.activityLevel === "string"
    || typeof safetyPolicyRaw.allowProactiveInteractions === "boolean";

  return {
    stateSchemaVersion:
      typeof raw.stateSchemaVersion === "number" ? raw.stateSchemaVersion : DEFAULT_STATE_SCHEMA_VERSION,
    installationId:
      typeof raw.installationId === "string" && raw.installationId.length > 0
        ? raw.installationId
        : randomUUID(),
    agentSlotId:
      typeof raw.agentSlotId === "string" && raw.agentSlotId.length > 0 ? raw.agentSlotId : slot,
    mode: raw.mode === "bound" ? "bound" : "public",
    skillRepo: normalizeOptionalString(raw.skillRepo),
    serverBaseUrl: normalizeOptionalString(raw.serverBaseUrl),
    agentId: normalizeOptionalString(raw.agentId),
    agentHandle: normalizeOptionalString(raw.agentHandle),
    accessToken: normalizeOptionalString(raw.accessToken),
    displayName: normalizeOptionalString(raw.displayName),
    bio: normalizeOptionalString(raw.bio),
    profileTags: Array.isArray(raw.profileTags)
      ? raw.profileTags
        .filter((entry) => typeof entry === "string")
        .map((entry) => String(entry).trim())
        .filter((entry) => entry.length > 0)
      : undefined,
    avatarUrl: raw.avatarUrl == null ? null : normalizeOptionalString(raw.avatarUrl) ?? null,
    avatarEmoji: raw.avatarEmoji == null ? null : normalizeOptionalString(raw.avatarEmoji) ?? null,
    avatarFileFingerprint: normalizeOptionalString(raw.avatarFileFingerprint),
    lastProfileSyncFingerprint: normalizeOptionalString(raw.lastProfileSyncFingerprint),
    runtimeName: normalizeOptionalString(raw.runtimeName),
    vendorName: normalizeOptionalString(raw.vendorName),
    transportMode: raw.transportMode === "hybrid" ? "hybrid" : "polling",
    pollingEnabled: typeof raw.pollingEnabled === "boolean" ? raw.pollingEnabled : undefined,
    webhookUrl: normalizeOptionalString(raw.webhookUrl) ?? null,
    safetyPolicy: hasSafetyPolicy ? (safetyPolicyRaw as AgentsChatState["safetyPolicy"]) : undefined,
    safetyPolicyFetchedAtUnixMs:
      typeof raw.safetyPolicyFetchedAtUnixMs === "number" ? raw.safetyPolicyFetchedAtUnixMs : undefined,
    lastConnectedAt: parseIso(raw.lastConnectedAt),
    lastInboundAt: parseIso(raw.lastInboundAt),
    lastOutboundAt: parseIso(raw.lastOutboundAt),
    lastPolicySyncAt: parseIso(raw.lastPolicySyncAt),
    lastDiscoveryAt: parseIso(raw.lastDiscoveryAt),
    lastProactiveActionAt: parseIso(raw.lastProactiveActionAt),
    lastProactiveActionType: parseProactiveActionType(raw.lastProactiveActionType),
    degradedReason: raw.degradedReason == null ? null : String(raw.degradedReason),
    conflictState: raw.conflictState == null ? null : String(raw.conflictState),
    proactiveActionLog: proactiveActionLog
      .filter((entry) => entry != null && typeof entry === "object")
      .reduce<NonNullable<AgentsChatState["proactiveActionLog"]>>((output, entry) => {
        const record = asRecord(entry);
        const type = parseProactiveActionType(record.type);
        const at = parseIso(record.at) ?? new Date(0).toISOString();
        if (!type || at === new Date(0).toISOString()) {
          return output;
        }
        output.push({
          type,
          at,
          targetId: normalizeOptionalString(record.targetId),
          threadId: normalizeOptionalString(record.threadId),
          agentId: normalizeOptionalString(record.agentId),
          agentIds: Array.isArray(record.agentIds)
            ? record.agentIds
              .map((value) => normalizeOptionalString(value))
              .filter((value): value is string => Boolean(value))
            : undefined
        });
        return output;
      }, []),
    lastError: raw.lastError == null ? null : String(raw.lastError)
  };
}

export function normalizePluginStateRoot(root: string): string {
  const normalizedPath = normalize(root);
  if (basename(normalizedPath).toLowerCase() === PLUGIN_ID) {
    mkdirSync(normalizedPath, { recursive: true });
    return normalizedPath;
  }
  const pluginRoot = join(normalizedPath, "plugins", PLUGIN_ID);
  mkdirSync(pluginRoot, { recursive: true });
  return pluginRoot;
}

export function resolveDefaultPluginStateRoot(): string {
  return normalizePluginStateRoot(resolveStateDir() || join(homedir(), ".openclaw"));
}

export function createAgentsChatStateStore(pluginStateRoot?: string | null): AgentsChatStateStore {
  return {
    pluginStateRoot: pluginStateRoot
      ? normalizePluginStateRoot(pluginStateRoot)
      : resolveDefaultPluginStateRoot()
  };
}

function resolveStore(store?: AgentsChatStateStore | null): AgentsChatStateStore {
  return store ?? createAgentsChatStateStore();
}

export function resolveInstallationFilePath(store?: AgentsChatStateStore | null): string {
  return join(resolveStore(store).pluginStateRoot, "installation.json");
}

export function resolveSlotStateDir(slot: string, store?: AgentsChatStateStore | null): string {
  const stateDir = join(resolveStore(store).pluginStateRoot, "slots", slot);
  mkdirSync(stateDir, { recursive: true });
  return stateDir;
}

export function resolveSlotStateFilePath(slot: string, store?: AgentsChatStateStore | null): string {
  return join(resolveSlotStateDir(slot, store), "state.json");
}

export function loadOrCreateInstallationId(store?: AgentsChatStateStore | null): string {
  const installationPath = resolveInstallationFilePath(store);
  if (existsSync(installationPath)) {
    const parsed = asRecord(JSON.parse(readFileSync(installationPath, "utf8")));
    if (typeof parsed.installationId === "string" && parsed.installationId.length > 0) {
      return parsed.installationId;
    }
  }
  const installationId = randomUUID();
  writeFileSync(
    installationPath,
    JSON.stringify(
      {
        installationId,
        createdAtUnixMs: Date.now()
      },
      null,
      2
    ),
    "utf8"
  );
  return installationId;
}

export function loadSlotState(slot: string, store?: AgentsChatStateStore | null): AgentsChatState {
  const targetStore = resolveStore(store);
  const statePath = resolveSlotStateFilePath(slot, targetStore);
  if (!existsSync(statePath)) {
    migrateLegacyStateIfNeeded(slot, targetStore);
  }
  if (!existsSync(statePath)) {
    return {
      stateSchemaVersion: DEFAULT_STATE_SCHEMA_VERSION,
      installationId: loadOrCreateInstallationId(targetStore),
      agentSlotId: slot,
      mode: "public"
    };
  }
  return normalizeState(slot, JSON.parse(readFileSync(statePath, "utf8")));
}

export function saveSlotState(
  slot: string,
  state: AgentsChatState,
  store?: AgentsChatStateStore | null
): void {
  const normalizedState = normalizeState(slot, state);
  const statePath = resolveSlotStateFilePath(slot, store);
  writeFileSync(statePath, JSON.stringify(normalizedState, null, 2), "utf8");
}

export function clearSlotState(slot: string, store?: AgentsChatStateStore | null): void {
  const targetStore = resolveStore(store);
  const installationId = loadOrCreateInstallationId(targetStore);
  saveSlotState(
    slot,
    {
      stateSchemaVersion: DEFAULT_STATE_SCHEMA_VERSION,
      installationId,
      agentSlotId: slot,
      mode: "public"
    },
    targetStore
  );
}

export function inspectLegacyStateSources(slot: string): AgentsChatLegacyStateSource[] {
  const openclawRoot = resolveStateDir() || join(homedir(), ".openclaw");
  const candidates: AgentsChatLegacyStateSource[] = [
    {
      kind: "openclaw-slot",
      path: join(openclawRoot, "slots", slot, "state.json")
    },
    {
      kind: "openclaw-plugin-slot",
      path: join(openclawRoot, "plugins", "agentschat", "slots", slot, "state.json")
    },
    {
      kind: "agents-chat-slot",
      path: join(homedir(), ".agents-chat-skill", "slots", slot, "state.json")
    },
    {
      kind: "agents-chat-root",
      path: join(homedir(), ".agents-chat-skill", "state.json")
    }
  ];
  return candidates.filter((candidate) => existsSync(candidate.path));
}

export function migrateLegacyStateIfNeeded(
  slot: string,
  store?: AgentsChatStateStore | null
): {
  migrated: boolean;
  sourcePath?: string;
} {
  const targetStore = resolveStore(store);
  const targetPath = resolveSlotStateFilePath(slot, targetStore);
  if (existsSync(targetPath)) {
    return { migrated: false };
  }

  const sources = inspectLegacyStateSources(slot);
  const source = sources[0];
  if (!source) {
    return { migrated: false };
  }

  const normalizedState = normalizeState(slot, JSON.parse(readFileSync(source.path, "utf8")));
  saveSlotState(slot, normalizedState, targetStore);
  return {
    migrated: true,
    sourcePath: source.path
  };
}
