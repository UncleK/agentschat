import { createHash, randomUUID } from "node:crypto";

import { DEFAULT_REPLY_MAX_CHARS } from "./constants.js";
import type { AgentsChatRuntimeContext } from "./context.js";
import type { AgentsChatAccountConfig } from "./types.js";
import { trimReplyText } from "./prompts.js";

const BANNED_VISIBLE_LINE_PATTERNS = [
  /^System \(untrusted\):/i,
  /^An async command you ran earlier has completed\./i,
  /^Current time:/i,
  /^You are an Agents Chat federated agent\./i,
  /^You$/i,
  /^\d{1,2}:\d{2}$/,
  /^↑[\d.]+[kKmM]?$/,
  /^↓[\d.]+[kKmM]?$/,
  /^R[\d.]+[kKmM]?$/,
  /^\d+% ctx$/i
];

function resolveFinalVisibleText(result: {
  meta: {
    finalAssistantVisibleText?: string;
  };
  payloads?: Array<{
    text?: string;
  }>;
  messagingToolSentTexts?: string[];
}): string {
  const metaText = result.meta.finalAssistantVisibleText?.trim();
  if (metaText) {
    return metaText;
  }

  const payloadText = (result.payloads ?? [])
    .map((payload) => payload.text?.trim())
    .filter((value): value is string => typeof value === "string" && value.length > 0)
    .join("\n\n")
    .trim();
  if (payloadText) {
    return payloadText;
  }

  const sentText = (result.messagingToolSentTexts ?? [])
    .map((value) => value.trim())
    .filter((value) => value.length > 0)
    .join("\n\n")
    .trim();
  return sentText;
}

function sanitizeVisibleText(value: string): string {
  const cleaned = value
    .split(/\r?\n/)
    .map((line) => line.trimEnd())
    .filter((line) => {
      if (line.trim().length === 0) {
        return true;
      }
      return !BANNED_VISIBLE_LINE_PATTERNS.some((pattern) => pattern.test(line.trim()));
    })
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();

  return cleaned;
}

function buildStableSessionId(sessionKey: string): string {
  const hash = createHash("sha1").update(sessionKey).digest("hex");
  return `agentschatapp-${hash.slice(0, 24)}`;
}

export function buildSessionKey(
  account: AgentsChatAccountConfig,
  kind: "dm" | "forum" | "debate" | "live" | "planner",
  threadId: string
): string {
  if (kind === "dm") {
    return `agentschatapp:${account.openclawAgent}:${threadId}`;
  }
  return `agentschatapp:${account.openclawAgent}:${kind}:${threadId}`;
}

export async function runEmbeddedReply(
  context: AgentsChatRuntimeContext,
  params: {
    account: AgentsChatAccountConfig;
    kind: "dm" | "forum" | "debate" | "live" | "planner";
    threadId: string;
    senderId?: string | null;
    senderName?: string | null;
    senderUsername?: string | null;
    prompt: string;
    timeoutMs?: number;
    maxChars?: number;
  }
): Promise<string> {
  const cfg = context.runtime.config.loadConfig();
  const sessionKey = buildSessionKey(params.account, params.kind, params.threadId);
  const sessionId = buildStableSessionId(sessionKey);
  const workspaceDir = context.runtime.agent.resolveAgentWorkspaceDir(cfg, params.account.openclawAgent);
  await context.runtime.agent.ensureAgentWorkspace({ dir: workspaceDir, ensureBootstrapFiles: true });
  const sessionFile = context.runtime.agent.session.resolveSessionFilePath(sessionId, undefined, {
    agentId: params.account.openclawAgent
  });

  const result = await context.runtime.agent.runEmbeddedPiAgent({
    sessionId,
    sessionKey,
    agentId: params.account.openclawAgent,
    messageChannel: "agentschatapp",
    messageProvider: "agentschatapp",
    agentAccountId: params.account.slot,
    messageTo: `${params.kind}:${params.threadId}`,
    messageThreadId: params.threadId,
    senderId: params.senderId ?? undefined,
    senderName: params.senderName ?? undefined,
    senderUsername: params.senderUsername ?? undefined,
    sessionFile,
    workspaceDir,
    prompt: params.prompt,
    disableMessageTool: true,
    requireExplicitMessageTarget: true,
    allowGatewaySubagentBinding: false,
    trigger: "user",
    timeoutMs: params.timeoutMs ?? context.runtime.agent.resolveAgentTimeoutMs({ cfg }),
    runId: randomUUID(),
    fastMode: false,
    bootstrapContextMode: "lightweight",
    bootstrapContextRunKind: "default",
    extraSystemPrompt: "",
    silentExpected: true
  });

  const output = trimReplyText(
    sanitizeVisibleText(resolveFinalVisibleText(result)),
    params.maxChars ?? DEFAULT_REPLY_MAX_CHARS
  );
  if (output.length === 0) {
    throw new Error("OpenClaw embedded run returned no visible text.");
  }
  return output;
}
