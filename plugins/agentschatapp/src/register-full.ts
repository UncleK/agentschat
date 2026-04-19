import type { OpenClawConfig, PluginLogger } from "openclaw/plugin-sdk/core";
import type { OpenClawPluginApi } from "openclaw/plugin-sdk/channel-core";

import {
  buildContextLogger,
  createAgentsChatRuntimeContext,
  derivePluginStateRootFromServiceStateDir
} from "./context.js";
import { registerAgentsChatCli } from "./cli.js";
import { startAgentsChatManager, stopAgentsChatManager } from "./worker.js";

type OpenClawPluginCliContext = {
  program: {
    command: (name: string) => any;
  };
  config: OpenClawConfig;
  workspaceDir?: string;
  logger: PluginLogger;
};

type OpenClawPluginServiceContext = {
  config: OpenClawConfig;
  workspaceDir?: string;
  stateDir: string;
  logger: PluginLogger;
};

function buildCliRuntimeContext(api: OpenClawPluginApi, ctx: OpenClawPluginCliContext) {
  return createAgentsChatRuntimeContext({
    runtime: api.runtime,
    logger: buildContextLogger(ctx.logger, "cli")
  });
}

function buildServiceRuntimeContext(api: OpenClawPluginApi, ctx: OpenClawPluginServiceContext) {
  return createAgentsChatRuntimeContext({
    runtime: api.runtime,
    logger: buildContextLogger(ctx.logger, "manager"),
    pluginStateRoot: derivePluginStateRootFromServiceStateDir(ctx.stateDir)
  });
}

export function registerAgentsChatFull(api: OpenClawPluginApi): void {
  api.registerCli((ctx) => registerAgentsChatCli(buildCliRuntimeContext(api, ctx), ctx), {
    commands: ["agentschatapp"],
    descriptors: [
      {
        name: "agentschatapp",
        description: "Manage agentschatapp plugin accounts",
        hasSubcommands: true
      }
    ]
  });

  api.registerService({
    id: "agentschatapp-worker-manager",
    start: async (ctx) => {
      await startAgentsChatManager(buildServiceRuntimeContext(api, ctx));
    },
    stop: async (ctx) => {
      await stopAgentsChatManager(buildServiceRuntimeContext(api, ctx));
    }
  });
}
