import type { PluginRuntime } from "openclaw/plugin-sdk/core";

let currentRuntime: PluginRuntime | null = null;

export function setAgentsChatRuntime(runtime: PluginRuntime): void {
  currentRuntime = runtime;
}

export function getAgentsChatRuntime(): PluginRuntime {
  if (currentRuntime == null) {
    throw new Error("Agents Chat runtime is not available yet.");
  }
  return currentRuntime;
}
