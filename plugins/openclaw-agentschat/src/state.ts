import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

import type { AgentsChatState } from "./types.js";
import { DEFAULT_STATE_SCHEMA_VERSION, PLUGIN_ID } from "./constants.js";
import { getAgentsChatRuntime } from "../runtime-api.js";

let serviceStateDir: string | null = null;

function asRecord(value: unknown): Record<string, unknown> {
  return value != null && typeof value === "object" ? (value as Record<string, unknown>) : {};
}

export function setAgentsChatServiceStateDir(nextStateDir: string | null): void {
  serviceStateDir = nextStateDir;
}

export function resolvePluginStateRoot(): string {
  if (serviceStateDir) {
    mkdirSync(serviceStateDir, { recursive: true });
    return serviceStateDir;
  }
  const runtime = getAgentsChatRuntime();
  const runtimeRoot = (() => {
    try {
      return runtime.state.resolveStateDir({});
    } catch {
      return join(homedir(), ".openclaw", "state");
    }
  })();
  const root = join(runtimeRoot, "plugins", PLUGIN_ID);
  mkdirSync(root, { recursive: true });
  return root;
}

export function resolveInstallationFilePath(): string {
  return join(resolvePluginStateRoot(), "installation.json");
}

export function resolveSlotStateDir(slot: string): string {
  const stateDir = join(resolvePluginStateRoot(), "slots", slot);
  mkdirSync(stateDir, { recursive: true });
  return stateDir;
}

export function resolveSlotStateFilePath(slot: string): string {
  return join(resolveSlotStateDir(slot), "state.json");
}

export function loadOrCreateInstallationId(): string {
  const installationPath = resolveInstallationFilePath();
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

export function loadSlotState(slot: string): AgentsChatState {
  const statePath = resolveSlotStateFilePath(slot);
  if (!existsSync(statePath)) {
    return {
      stateSchemaVersion: DEFAULT_STATE_SCHEMA_VERSION,
      installationId: loadOrCreateInstallationId(),
      agentSlotId: slot,
      mode: "public"
    };
  }
  const raw = asRecord(JSON.parse(readFileSync(statePath, "utf8")));
  const safetyPolicyRaw = asRecord(raw.safetyPolicy);
  const hasSafetyPolicy =
    typeof safetyPolicyRaw.activityLevel === "string"
    || typeof safetyPolicyRaw.allowProactiveInteractions === "boolean";
  return {
    stateSchemaVersion:
      typeof raw.stateSchemaVersion === "number" ? raw.stateSchemaVersion : DEFAULT_STATE_SCHEMA_VERSION,
    installationId:
      typeof raw.installationId === "string" && raw.installationId.length > 0
        ? raw.installationId
        : loadOrCreateInstallationId(),
    agentSlotId: typeof raw.agentSlotId === "string" && raw.agentSlotId.length > 0 ? raw.agentSlotId : slot,
    mode: raw.mode === "bound" ? "bound" : "public",
    skillRepo: typeof raw.skillRepo === "string" ? raw.skillRepo : undefined,
    serverBaseUrl: typeof raw.serverBaseUrl === "string" ? raw.serverBaseUrl : undefined,
    agentId: typeof raw.agentId === "string" ? raw.agentId : undefined,
    agentHandle: typeof raw.agentHandle === "string" ? raw.agentHandle : undefined,
    accessToken: typeof raw.accessToken === "string" ? raw.accessToken : undefined,
    displayName: typeof raw.displayName === "string" ? raw.displayName : undefined,
    runtimeName: typeof raw.runtimeName === "string" ? raw.runtimeName : undefined,
    vendorName: typeof raw.vendorName === "string" ? raw.vendorName : undefined,
    transportMode: raw.transportMode === "hybrid" ? "hybrid" : "polling",
    pollingEnabled: typeof raw.pollingEnabled === "boolean" ? raw.pollingEnabled : undefined,
    webhookUrl: typeof raw.webhookUrl === "string" ? raw.webhookUrl : undefined,
    safetyPolicy: hasSafetyPolicy ? (safetyPolicyRaw as AgentsChatState["safetyPolicy"]) : undefined,
    safetyPolicyFetchedAtUnixMs:
      typeof raw.safetyPolicyFetchedAtUnixMs === "number" ? raw.safetyPolicyFetchedAtUnixMs : undefined,
    lastConnectedAt: typeof raw.lastConnectedAt === "string" ? raw.lastConnectedAt : undefined,
    lastInboundAt: typeof raw.lastInboundAt === "string" ? raw.lastInboundAt : undefined,
    lastOutboundAt: typeof raw.lastOutboundAt === "string" ? raw.lastOutboundAt : undefined,
    lastError: raw.lastError == null ? null : String(raw.lastError)
  };
}

export function saveSlotState(slot: string, state: AgentsChatState): void {
  const statePath = resolveSlotStateFilePath(slot);
  writeFileSync(statePath, JSON.stringify(state, null, 2), "utf8");
}

export function clearSlotState(slot: string): void {
  const installationId = loadOrCreateInstallationId();
  saveSlotState(slot, {
    stateSchemaVersion: DEFAULT_STATE_SCHEMA_VERSION,
    installationId,
    agentSlotId: slot,
    mode: "public"
  });
}
