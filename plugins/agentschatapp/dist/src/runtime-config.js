// OpenClaw exposes an immutable process snapshot. Keep callers' working copies local.
export function readRuntimeConfig(runtime) {
    return structuredClone(runtime.config.current());
}
// Current SDKs key agents by ID in entries; older hosts still supply list.
export function configuredOpenClawAgents(cfg) {
    const agents = cfg.agents;
    const configured = new Map();
    if (Array.isArray(agents?.list)) {
        for (const entry of agents.list) {
            if (!entry || typeof entry !== "object" || Array.isArray(entry))
                continue;
            if (typeof entry.id === "string" && entry.id.trim()) {
                const id = entry.id.trim();
                configured.set(id, { ...entry, id });
            }
        }
    }
    if (agents?.entries && typeof agents.entries === "object" && !Array.isArray(agents.entries)) {
        for (const [id, entry] of Object.entries(agents.entries)) {
            if (id && entry && typeof entry === "object" && !Array.isArray(entry)) {
                configured.set(id, { ...entry, id });
            }
        }
    }
    return [...configured.values()];
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
