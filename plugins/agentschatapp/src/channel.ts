import type { OpenClawConfig } from "openclaw/plugin-sdk/core";
import { createChannelPluginBase } from "openclaw/plugin-sdk/channel-core";

import { CHANNEL_LABEL } from "./constants.js";
import {
  agentsChatChannelConfigSchema,
  agentsChatConfigAdapter,
  agentsChatSetupAdapter,
  resolveAgentsChatAccount
} from "./config.js";
import { buildSnapshotForAccount } from "./worker.js";
import { readDirectory } from "./launcher.js";
import { loadSlotState } from "./state.js";
import type { AgentsChatAccountConfig } from "./types.js";

function normalizeOptionalString(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

const resolverAdapter = {
  async resolveTargets({
    cfg,
    accountId,
    inputs,
    kind
  }: {
    cfg: OpenClawConfig;
    accountId?: string | null;
    inputs: string[];
    kind: string;
  }) {
    const account = resolveAgentsChatAccount(cfg, accountId);
    const state = loadSlotState(account.slot);
    if (!state.serverBaseUrl || !state.accessToken) {
      return inputs.map((input) => ({
        input,
        resolved: false,
        note: "slot is not connected yet"
      }));
    }

    const directory = await readDirectory(state.serverBaseUrl, state.accessToken);
    const agents = Array.isArray(directory.agents) ? directory.agents : [];
    return inputs.map((input) => {
      const normalized = input.trim().toLowerCase();
      const match = agents.find((entry) => {
        if (entry == null || typeof entry !== "object") {
          return false;
        }
        const record = entry as Record<string, unknown>;
        const handle = normalizeOptionalString(record.handle)?.toLowerCase();
        const displayName = normalizeOptionalString(record.displayName)?.toLowerCase();
        return handle === normalized || displayName === normalized;
      }) as Record<string, unknown> | undefined;

      if (!match) {
        return {
          input,
          resolved: false,
          note: `no ${kind} matched`
        };
      }

      return {
        input,
        resolved: true,
        id: normalizeOptionalString(match.id),
        name: normalizeOptionalString(match.displayName) ?? normalizeOptionalString(match.handle),
        note: "matched from Agents Chat directory"
      };
    });
  }
};

export const agentsChatPlugin = {
  ...createChannelPluginBase<AgentsChatAccountConfig>({
    id: "agentschatapp",
    meta: {
      label: CHANNEL_LABEL,
      selectionLabel: CHANNEL_LABEL,
      detailLabel: CHANNEL_LABEL,
      docsPath: "/channels/agentschatapp",
      docsLabel: "agentschatapp",
      blurb: "Run Agents Chat federated agents natively inside OpenClaw.",
      selectionExtras: ["https://agentschat.app"],
      markdownCapable: true,
      systemImage: "network",
      showConfigured: true,
      showInSetup: true
    },
    capabilities: {
      chatTypes: ["direct", "group", "thread"],
      reply: true,
      threads: true,
      nativeCommands: true
    },
    reload: {
      configPrefixes: ["channels.agentschatapp", "channels.agentschat"]
    },
    configSchema: agentsChatChannelConfigSchema,
    config: agentsChatConfigAdapter,
    setup: agentsChatSetupAdapter
  }),
  resolver: resolverAdapter,
  status: {
    buildAccountSnapshot: async ({
      account
    }: {
      account: AgentsChatAccountConfig;
    }) => buildSnapshotForAccount(account),
    resolveAccountState: ({
      configured,
      enabled,
      account
    }: {
      configured: boolean;
      enabled: boolean;
      account: AgentsChatAccountConfig;
    }) => {
      const snapshot = buildSnapshotForAccount(account);
      if (!enabled) {
        return "disabled";
      }
      if (!configured) {
        return "not configured";
      }
      return snapshot.connected ? "linked" : "configured";
    }
  }
} as any;
