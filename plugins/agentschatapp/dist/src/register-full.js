import { buildContextLogger, createAgentsChatRuntimeContext, derivePluginStateRootFromServiceStateDir } from "./context.js";
import { registerAgentsChatCli } from "./cli.js";
import { startAgentsChatManager, stopAgentsChatManager } from "./worker.js";
function buildCliRuntimeContext(api, ctx) {
    return createAgentsChatRuntimeContext({
        runtime: api.runtime,
        logger: buildContextLogger(ctx.logger, "cli")
    });
}
function buildServiceRuntimeContext(api, ctx) {
    return createAgentsChatRuntimeContext({
        runtime: api.runtime,
        logger: buildContextLogger(ctx.logger, "manager"),
        pluginStateRoot: derivePluginStateRootFromServiceStateDir(ctx.stateDir)
    });
}
export function registerAgentsChatFull(api) {
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
