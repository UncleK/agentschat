import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
export const PLUGIN_ID = "agentschatapp";
export const CHANNEL_LABEL = "agentschatapp";
export const PACKAGE_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
export const DEFAULT_SERVER_BASE_URL = "https://agentschat.app";
export const DEFAULT_OPENCLAW_AGENT = "main";
export const DEFAULT_SLOT = "openclaw-main";
export const DEFAULT_TRANSPORT = "polling";
export const DEFAULT_RUNTIME_NAME = "agentschatapp";
export const DEFAULT_VENDOR_NAME = "OpenClaw";
export const DEFAULT_POLL_WAIT_SECONDS = 20;
export const DEFAULT_POLL_BACKOFF_SECONDS = [1, 2, 5, 10, 20, 30];
export const DEFAULT_ACTION_TIMEOUT_SECONDS = 30;
export const DEFAULT_HISTORY_LIMIT = 24;
export const DEFAULT_REPLY_MAX_CHARS = 4000;
export const DEFAULT_MANAGER_INTERVAL_MS = 15000;
export const DEFAULT_STATE_SCHEMA_VERSION = 1;
export const DEFAULT_SAFETY_POLICY_REFRESH_MS = 60000;
export const DEFAULT_DISCOVERY_INTERVAL_MS = 5 * 60 * 1000;
export const DEFAULT_DISCOVERY_JITTER_MS = 15 * 1000;
export const DEFAULT_DISCOVERY_TOPIC_LIMIT = 10;
export const DEFAULT_RECENT_TOPIC_LIMIT = 20;
export const DEFAULT_MAX_FORUM_REPLY_CANDIDATES = 3;
export const DEFAULT_MAX_PROACTIVE_REPLIES_PER_HOUR = 5;
export const DEFAULT_MAX_PROACTIVE_TOPICS_PER_DAY = 2;
export const DEFAULT_MAX_PROACTIVE_DEBATES_PER_DAY = 2;
export const DEFAULT_MAX_PROACTIVE_FOLLOWS_PER_DAY = 5;
export const DEFAULT_THREAD_REPLY_COOLDOWN_MS = 6 * 60 * 60 * 1000;
export const DEFAULT_THREAD_MAX_AGE_MS = 24 * 60 * 60 * 1000;
export const DEFAULT_TOPIC_CREATE_COOLDOWN_MS = 90 * 60 * 1000;
export const DEFAULT_DEBATE_CREATE_COOLDOWN_MS = 6 * 60 * 60 * 1000;
export const DEFAULT_DISCOVERY_HISTORY_LIMIT = 96;
export const NO_REPLY_SENTINEL = "NO_REPLY";
export const NO_TOPIC_SENTINEL = "NO_TOPIC";
export const NO_DEBATE_SENTINEL = "NO_DEBATE";
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
    "agentschatapp/0.1.2"
].join(" ");
export const SLOT_PATTERN = /[^A-Za-z0-9._-]+/g;
