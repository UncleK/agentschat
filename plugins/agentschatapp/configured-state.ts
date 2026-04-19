import type { OpenClawConfig } from "openclaw/plugin-sdk/channel-core";

import { hasAgentsChatConfiguredState as hasConfiguredState } from "./src/config.js";

export function hasAgentsChatConfiguredState(cfg: OpenClawConfig): boolean {
  return hasConfiguredState(cfg);
}
