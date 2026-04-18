import { createHash, randomUUID } from "node:crypto";
import { DEFAULT_REPLY_MAX_CHARS } from "./constants.js";
import { getAgentsChatRuntime } from "../runtime-api.js";
import { trimReplyText } from "./prompts.js";
function resolveFinalVisibleText(result) {
    const metaText = result.meta.finalAssistantVisibleText?.trim();
    if (metaText) {
        return metaText;
    }
    const payloadText = (result.payloads ?? [])
        .map((payload) => payload.text?.trim())
        .filter((value) => typeof value === "string" && value.length > 0)
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
function buildStableSessionId(sessionKey) {
    const hash = createHash("sha1").update(sessionKey).digest("hex");
    return `agentschat-${hash.slice(0, 24)}`;
}
export function buildSessionKey(account, kind, threadId) {
    if (kind === "dm") {
        return `agentschat:${account.openclawAgent}:${threadId}`;
    }
    return `agentschat:${account.openclawAgent}:${kind}:${threadId}`;
}
export async function runEmbeddedReply(params) {
    const runtime = getAgentsChatRuntime();
    const cfg = runtime.config.loadConfig();
    const sessionKey = buildSessionKey(params.account, params.kind, params.threadId);
    const sessionId = buildStableSessionId(sessionKey);
    const workspaceDir = runtime.agent.resolveAgentWorkspaceDir(cfg, params.account.openclawAgent);
    await runtime.agent.ensureAgentWorkspace({ dir: workspaceDir, ensureBootstrapFiles: true });
    const sessionFile = runtime.agent.session.resolveSessionFilePath(sessionId, undefined, {
        agentId: params.account.openclawAgent
    });
    const result = await runtime.agent.runEmbeddedPiAgent({
        sessionId,
        sessionKey,
        agentId: params.account.openclawAgent,
        messageChannel: "agentschat",
        messageProvider: "agentschat",
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
        timeoutMs: params.timeoutMs ?? runtime.agent.resolveAgentTimeoutMs({ cfg }),
        runId: randomUUID(),
        fastMode: false,
        bootstrapContextMode: "lightweight",
        bootstrapContextRunKind: "default",
        extraSystemPrompt: "",
        silentExpected: true
    });
    const output = trimReplyText(resolveFinalVisibleText(result), params.maxChars ?? DEFAULT_REPLY_MAX_CHARS);
    if (output.length === 0) {
        throw new Error("OpenClaw embedded run returned no visible text.");
    }
    return output;
}
