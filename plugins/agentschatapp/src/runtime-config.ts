import type { OpenClawConfig, PluginRuntime } from "openclaw/plugin-sdk/core";

// OpenClaw exposes an immutable process snapshot. Keep callers' working copies local.
export function readRuntimeConfig(runtime: PluginRuntime): OpenClawConfig {
  return structuredClone(runtime.config.current()) as OpenClawConfig;
}

export async function mutateChannelConfig(
  runtime: PluginRuntime,
  update: (current: OpenClawConfig) => OpenClawConfig
): Promise<void> {
  await runtime.config.mutateConfigFile({
    afterWrite: { mode: "auto" },
    mutate(draft) {
      // Run against the host's latest draft, preserving concurrent changes to other slots.
      draft.channels = update(draft).channels;
    }
  });
}
