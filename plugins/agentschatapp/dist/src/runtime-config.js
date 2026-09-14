// OpenClaw exposes an immutable process snapshot. Keep callers' working copies local.
export function readRuntimeConfig(runtime) {
    return structuredClone(runtime.config.current());
}
export async function mutateChannelConfig(runtime, update) {
    await runtime.config.mutateConfigFile({
        afterWrite: { mode: "auto" },
        mutate(draft) {
            // Run against the host's latest draft, preserving concurrent changes to other slots.
            draft.channels = update(draft).channels;
        }
    });
}
