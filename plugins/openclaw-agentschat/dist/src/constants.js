import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
export const PLUGIN_ID = "agentschat";
export const CHANNEL_LABEL = "Agents Chat";
export const PACKAGE_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
export const BUNDLED_SKILL_ROOT = join(PACKAGE_ROOT, "skills", "agents-chat-v1");
export const BUNDLED_SKILL_MAIN = join(BUNDLED_SKILL_ROOT, "SKILL.md");
export const DEFAULT_SERVER_BASE_URL = "https://agentschat.app";
export const DEFAULT_OPENCLAW_AGENT = "main";
export const DEFAULT_SLOT = "openclaw-main";
export const DEFAULT_TRANSPORT = "polling";
export const DEFAULT_RUNTIME_NAME = "OpenClaw Agents Chat Plugin";
export const DEFAULT_VENDOR_NAME = "OpenClaw";
export const DEFAULT_POLL_WAIT_SECONDS = 20;
export const DEFAULT_POLL_BACKOFF_SECONDS = [1, 2, 5, 10, 20, 30];
export const DEFAULT_ACTION_TIMEOUT_SECONDS = 30;
export const DEFAULT_HISTORY_LIMIT = 24;
export const DEFAULT_REPLY_MAX_CHARS = 4000;
export const DEFAULT_MANAGER_INTERVAL_MS = 15000;
export const DEFAULT_STATE_SCHEMA_VERSION = 1;
export const DEFAULT_SAFETY_POLICY_REFRESH_MS = 60000;
export const NO_REPLY_SENTINEL = "NO_REPLY";
export const SYSTEM_PROMPT = [
    "You are an Agents Chat federated agent inside OpenClaw.",
    "Speak as the agent itself.",
    "Use plain text only.",
    "Do not output JSON, code fences, internal reasoning, tool traces, or system logs."
].join(" ");
export const HTTP_USER_AGENT = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    "AppleWebKit/537.36 (KHTML, like Gecko)",
    "Chrome/135.0.0.0 Safari/537.36",
    "AgentsChatOpenClaw/0.1.0"
].join(" ");
export const SLOT_PATTERN = /[^A-Za-z0-9._-]+/g;
