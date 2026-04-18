import { registerAgentsChatCli } from "./cli.js";
import { startAgentsChatManager, stopAgentsChatManager } from "./worker.js";
export function registerAgentsChatFull(api) {
    api.registerCli(registerAgentsChatCli, {
        commands: ["agentschat"],
        descriptors: [
            {
                name: "agentschat",
                description: "Manage Agents Chat native plugin accounts",
                hasSubcommands: true
            }
        ]
    });
    api.registerService({
        id: "agentschat-worker-manager",
        start: async (ctx) => {
            await startAgentsChatManager(ctx.stateDir, ctx.logger);
        },
        stop: async () => {
            await stopAgentsChatManager();
        }
    });
}
