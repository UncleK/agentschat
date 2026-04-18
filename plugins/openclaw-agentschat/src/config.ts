import type { OpenClawConfig } from "openclaw/plugin-sdk/core";

import {
  DEFAULT_OPENCLAW_AGENT,
  DEFAULT_SERVER_BASE_URL,
  DEFAULT_SLOT,
  DEFAULT_TRANSPORT
} from "./constants.js";
import type { AgentsChatAccountConfig, AgentsChatChannelSection, AgentsChatMode, AgentsChatTransport } from "./types.js";

type RuntimeConfigIssue = {
  path?: Array<string | number>;
  message?: string;
  code?: string;
} & Record<string, unknown>;

type RuntimeParseResult =
  | {
      success: true;
      data: unknown;
    }
  | {
      success: false;
      issues: RuntimeConfigIssue[];
    };

type ChannelAccountSnapshot = {
  accountId: string;
  name?: string;
  enabled?: boolean;
  configured?: boolean;
  mode?: string;
  baseUrl?: string;
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

function normalizeMode(value: unknown): AgentsChatMode {
  return value === "bound" ? "bound" : "public";
}

function normalizeTransport(value: unknown): AgentsChatTransport {
  return value === "hybrid" ? "hybrid" : "polling";
}

function normalizeBoolean(value: unknown, fallback: boolean): boolean {
  return typeof value === "boolean" ? value : fallback;
}

export function getAgentsChatChannelSection(cfg: OpenClawConfig): AgentsChatChannelSection {
  const channels = asRecord(cfg.channels);
  return asRecord(channels.agentschat) as AgentsChatChannelSection;
}

export function listAgentsChatAccounts(cfg: OpenClawConfig): AgentsChatAccountConfig[] {
  const section = getAgentsChatChannelSection(cfg);
  if (!Array.isArray(section.accounts)) {
    return [];
  }

  const accounts: AgentsChatAccountConfig[] = [];
  for (const raw of section.accounts) {
    const record = asRecord(raw);
    const slot = normalizeOptionalString(record.slot);
    if (!slot) {
      continue;
    }
    accounts.push({
      openclawAgent: normalizeOptionalString(record.openclawAgent) ?? DEFAULT_OPENCLAW_AGENT,
      slot,
      mode: normalizeMode(record.mode),
      launcherUrl: normalizeOptionalString(record.launcherUrl),
      serverBaseUrl: normalizeOptionalString(record.serverBaseUrl),
      handle: normalizeOptionalString(record.handle),
      displayName: normalizeOptionalString(record.displayName),
      autoStart: normalizeBoolean(record.autoStart, true),
      transport: normalizeTransport(record.transport),
      webhookBaseUrl: normalizeOptionalString(record.webhookBaseUrl)
    });
  }
  return accounts;
}

export function resolveAgentsChatAccount(
  cfg: OpenClawConfig,
  accountId?: string | null
): AgentsChatAccountConfig {
  const accounts = listAgentsChatAccounts(cfg);
  const requestedId = normalizeOptionalString(accountId) ?? accounts[0]?.slot ?? DEFAULT_SLOT;
  return accounts.find((account) => account.slot === requestedId) ?? {
    openclawAgent: DEFAULT_OPENCLAW_AGENT,
    slot: requestedId,
    mode: "public",
    serverBaseUrl: DEFAULT_SERVER_BASE_URL,
    autoStart: true,
    transport: DEFAULT_TRANSPORT
  };
}

export function findAgentsChatAccount(
  cfg: OpenClawConfig,
  slot: string
): AgentsChatAccountConfig | undefined {
  return listAgentsChatAccounts(cfg).find((account) => account.slot === slot);
}

export function isConfiguredAgentsChatAccount(account: AgentsChatAccountConfig): boolean {
  if (account.mode === "bound") {
    return typeof account.launcherUrl === "string" && account.launcherUrl.length > 0;
  }
  return typeof account.serverBaseUrl === "string" && account.serverBaseUrl.length > 0;
}

export function hasAgentsChatConfiguredState(cfg: OpenClawConfig): boolean {
  return listAgentsChatAccounts(cfg).some(isConfiguredAgentsChatAccount);
}

export function upsertAgentsChatAccount(
  cfg: OpenClawConfig,
  account: AgentsChatAccountConfig
): OpenClawConfig {
  const nextCfg = structuredClone(cfg);
  if (nextCfg.channels == null || typeof nextCfg.channels !== "object") {
    nextCfg.channels = {};
  }

  const channels = nextCfg.channels as Record<string, unknown>;
  const section = asRecord(channels.agentschat);
  const nextAccounts = Array.isArray(section.accounts) ? [...section.accounts] : [];
  const serialized = {
    openclawAgent: account.openclawAgent,
    slot: account.slot,
    mode: account.mode,
    launcherUrl: account.launcherUrl,
    serverBaseUrl: account.serverBaseUrl,
    handle: account.handle,
    displayName: account.displayName,
    autoStart: account.autoStart ?? true,
    transport: account.transport ?? DEFAULT_TRANSPORT,
    webhookBaseUrl: account.webhookBaseUrl
  };

  const existingIndex = nextAccounts.findIndex((entry) => asRecord(entry).slot === account.slot);
  if (existingIndex >= 0) {
    nextAccounts[existingIndex] = serialized;
  } else {
    nextAccounts.push(serialized);
  }

  channels.agentschat = {
    ...section,
    accounts: nextAccounts
  };
  return nextCfg;
}

export function removeAgentsChatAccount(cfg: OpenClawConfig, slot: string): OpenClawConfig {
  const nextCfg = structuredClone(cfg);
  if (nextCfg.channels == null || typeof nextCfg.channels !== "object") {
    return nextCfg;
  }
  const channels = nextCfg.channels as Record<string, unknown>;
  const section = asRecord(channels.agentschat);
  const accounts = Array.isArray(section.accounts) ? section.accounts : [];
  channels.agentschat = {
    ...section,
    accounts: accounts.filter((entry) => asRecord(entry).slot !== slot)
  };
  return nextCfg;
}

export function setAgentsChatAccountEnabled(
  cfg: OpenClawConfig,
  slot: string,
  enabled: boolean
): OpenClawConfig {
  const account = resolveAgentsChatAccount(cfg, slot);
  return upsertAgentsChatAccount(cfg, {
    ...account,
    autoStart: enabled
  });
}

export function accountFingerprint(account: AgentsChatAccountConfig): string {
  return JSON.stringify({
    openclawAgent: account.openclawAgent,
    slot: account.slot,
    mode: account.mode,
    launcherUrl: account.launcherUrl,
    serverBaseUrl: account.serverBaseUrl,
    handle: account.handle,
    displayName: account.displayName,
    autoStart: account.autoStart ?? true,
    transport: account.transport ?? DEFAULT_TRANSPORT,
    webhookBaseUrl: account.webhookBaseUrl
  });
}

function validateAccount(value: unknown, index: number): RuntimeConfigIssue[] {
  const issues: RuntimeConfigIssue[] = [];
  const record = asRecord(value);
  const slot = normalizeOptionalString(record.slot);
  const openclawAgent = normalizeOptionalString(record.openclawAgent);
  if (!slot) {
    issues.push({
      path: ["accounts", index, "slot"],
      message: "slot is required"
    });
  }
  if (!openclawAgent) {
    issues.push({
      path: ["accounts", index, "openclawAgent"],
      message: "openclawAgent is required"
    });
  }
  if (record.mode !== "public" && record.mode !== "bound") {
    issues.push({
      path: ["accounts", index, "mode"],
      message: "mode must be public or bound"
    });
  }
  if (record.transport != null && record.transport !== "polling" && record.transport !== "hybrid") {
    issues.push({
      path: ["accounts", index, "transport"],
      message: "transport must be polling or hybrid"
    });
  }
  return issues;
}

function validateSection(value: unknown): RuntimeParseResult {
  const record = asRecord(value);
  const issues: RuntimeConfigIssue[] = [];
  const accounts = record.accounts;
  if (accounts != null && !Array.isArray(accounts)) {
    issues.push({
      path: ["accounts"],
      message: "accounts must be an array"
    });
  }
  if (Array.isArray(accounts)) {
    const seenSlots = new Set<string>();
    accounts.forEach((account, index) => {
      issues.push(...validateAccount(account, index));
      const slot = normalizeOptionalString(asRecord(account).slot);
      if (slot) {
        if (seenSlots.has(slot)) {
          issues.push({
            path: ["accounts", index, "slot"],
            message: "slot must be unique"
          });
        }
        seenSlots.add(slot);
      }
    });
  }

  if (issues.length > 0) {
    return {
      success: false,
      issues
    };
  }

  return {
    success: true,
    data: value
  };
}

const configSchemaJson = {
  type: "object",
  additionalProperties: false,
  properties: {
    accounts: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["openclawAgent", "slot", "mode"],
        properties: {
          openclawAgent: { type: "string", minLength: 1 },
          slot: { type: "string", minLength: 1 },
          mode: { type: "string", enum: ["public", "bound"] },
          launcherUrl: { type: "string" },
          serverBaseUrl: { type: "string" },
          handle: { type: "string" },
          displayName: { type: "string" },
          autoStart: { type: "boolean", default: true },
          transport: { type: "string", enum: ["polling", "hybrid"], default: "polling" },
          webhookBaseUrl: { type: "string" }
        }
      }
    }
  }
} satisfies Record<string, unknown>;

export const agentsChatChannelConfigSchema = {
  schema: configSchemaJson,
  runtime: {
    safeParse: validateSection
  }
};

export const agentsChatConfigAdapter = {
  listAccountIds: (cfg: OpenClawConfig) => listAgentsChatAccounts(cfg).map((account) => account.slot),
  resolveAccount: (cfg: OpenClawConfig, accountId?: string | null) => resolveAgentsChatAccount(cfg, accountId),
  inspectAccount: (cfg: OpenClawConfig, accountId?: string | null) => resolveAgentsChatAccount(cfg, accountId),
  defaultAccountId: (cfg: OpenClawConfig) => listAgentsChatAccounts(cfg)[0]?.slot ?? DEFAULT_SLOT,
  setAccountEnabled: ({
    cfg,
    accountId,
    enabled
  }: {
    cfg: OpenClawConfig;
    accountId: string;
    enabled: boolean;
  }) => setAgentsChatAccountEnabled(cfg, accountId, enabled),
  deleteAccount: ({
    cfg,
    accountId
  }: {
    cfg: OpenClawConfig;
    accountId: string;
  }) => removeAgentsChatAccount(cfg, accountId),
  isEnabled: (account: AgentsChatAccountConfig) => account.autoStart !== false,
  disabledReason: () => "autoStart is disabled",
  isConfigured: (account: AgentsChatAccountConfig) => isConfiguredAgentsChatAccount(account),
  unconfiguredReason: (account: AgentsChatAccountConfig) => {
    return account.mode === "bound"
      ? "bound mode requires launcherUrl"
      : "public mode requires serverBaseUrl";
  },
  describeAccount: (account: AgentsChatAccountConfig) => {
    const snapshot: ChannelAccountSnapshot = {
      accountId: account.slot,
      name: account.displayName ?? account.slot,
      enabled: account.autoStart !== false,
      configured: isConfiguredAgentsChatAccount(account),
      mode: account.mode,
      baseUrl: account.serverBaseUrl ?? DEFAULT_SERVER_BASE_URL
    };
    return snapshot;
  },
  hasConfiguredState: ({ cfg }: { cfg: OpenClawConfig }) => hasAgentsChatConfiguredState(cfg)
};

export const agentsChatSetupAdapter = {
  resolveAccountId: ({
    accountId,
    input
  }: {
    accountId?: string;
    input?: unknown;
  }) => {
    const requested = normalizeOptionalString(accountId) ?? normalizeOptionalString(asRecord(input).slot);
    return requested ?? DEFAULT_SLOT;
  },
  applyAccountConfig: ({
    cfg,
    accountId,
    input
  }: {
    cfg: OpenClawConfig;
    accountId: string;
    input: unknown;
  }) => {
    const record = asRecord(input);
    return upsertAgentsChatAccount(cfg, {
      openclawAgent: normalizeOptionalString(record.openclawAgent) ?? DEFAULT_OPENCLAW_AGENT,
      slot: accountId,
      mode: normalizeMode(record.mode),
      launcherUrl: normalizeOptionalString(record.launcherUrl),
      serverBaseUrl: normalizeOptionalString(record.serverBaseUrl) ?? DEFAULT_SERVER_BASE_URL,
      handle: normalizeOptionalString(record.handle),
      displayName: normalizeOptionalString(record.displayName),
      autoStart: normalizeBoolean(record.autoStart, true),
      transport: normalizeTransport(record.transport),
      webhookBaseUrl: normalizeOptionalString(record.webhookBaseUrl)
    });
  },
  validateInput: ({ accountId }: { accountId: string }) => {
    return accountId.trim().length > 0 ? null : "slot is required";
  }
};
