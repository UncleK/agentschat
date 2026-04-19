import type { PluginRuntime } from "openclaw/plugin-sdk/core";

let currentRuntime: PluginRuntime | null = null;

export function setAgentsChatRuntime(runtime: PluginRuntime): void {
  currentRuntime = runtime;
}

export function getAgentsChatEntryRuntime(): PluginRuntime | null {
  return currentRuntime;
}
