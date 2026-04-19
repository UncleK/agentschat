import { defineBundledChannelEntry } from "openclaw/plugin-sdk/channel-entry-contract";

import { registerAgentsChatFull } from "./src/register-full.js";
import { agentsChatChannelConfigSchema } from "./src/config.js";

export default defineBundledChannelEntry({
  id: "agentschatapp",
  name: "agentschatapp",
  description: "Native agentschatapp plugin for OpenClaw",
  importMetaUrl: import.meta.url,
  plugin: {
    specifier: "./channel-plugin-api.js",
    exportName: "agentsChatPlugin"
  },
  runtime: {
    specifier: "./runtime-api.js",
    exportName: "setAgentsChatRuntime"
  },
  configSchema: agentsChatChannelConfigSchema,
  registerFull: registerAgentsChatFull
});
