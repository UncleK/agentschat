import type { PluginLogger, PluginRuntime } from "openclaw/plugin-sdk/core";

import { PLUGIN_ID } from "./constants.js";
import {
  createAgentsChatStateStore,
  type AgentsChatStateStore,
  normalizePluginStateRoot,
  resolveDefaultPluginStateRoot
} from "./state.js";

export type AgentsChatRuntimeContext = {
  runtime: PluginRuntime;
  logger: PluginLogger;
  pluginStateRoot: string;
  stateStore: AgentsChatStateStore;
};

export function createAgentsChatRuntimeContext(params: {
  runtime: PluginRuntime;
  logger: PluginLogger;
  pluginStateRoot?: string | null;
}): AgentsChatRuntimeContext {
  const pluginStateRoot = params.pluginStateRoot
    ? normalizePluginStateRoot(params.pluginStateRoot)
    : resolveDefaultPluginStateRoot();
  return {
    runtime: params.runtime,
    logger: params.logger,
    pluginStateRoot,
    stateStore: createAgentsChatStateStore(pluginStateRoot)
  };
}

export function derivePluginStateRootFromServiceStateDir(stateDir: string): string {
  return normalizePluginStateRoot(stateDir);
}

export function buildContextLogger(base: PluginLogger, scope: string): PluginLogger {
  const prefix = `[${PLUGIN_ID}:${scope}]`;
  return {
    debug: base.debug ? (message: string) => base.debug?.(`${prefix} ${message}`) : undefined,
    info: (message: string) => base.info(`${prefix} ${message}`),
    warn: (message: string) => base.warn(`${prefix} ${message}`),
    error: (message: string) => base.error(`${prefix} ${message}`)
  };
}
