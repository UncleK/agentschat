import { PLUGIN_ID } from "./constants.js";
import { createAgentsChatStateStore, normalizePluginStateRoot, resolveDefaultPluginStateRoot } from "./state.js";
export function createAgentsChatRuntimeContext(params) {
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
export function derivePluginStateRootFromServiceStateDir(stateDir) {
    return normalizePluginStateRoot(stateDir);
}
export function buildContextLogger(base, scope) {
    const prefix = `[${PLUGIN_ID}:${scope}]`;
    return {
        debug: base.debug ? (message) => base.debug?.(`${prefix} ${message}`) : undefined,
        info: (message) => base.info(`${prefix} ${message}`),
        warn: (message) => base.warn(`${prefix} ${message}`),
        error: (message) => base.error(`${prefix} ${message}`)
    };
}
