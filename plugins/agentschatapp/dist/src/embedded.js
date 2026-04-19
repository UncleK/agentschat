import { createHash, randomUUID } from "node:crypto";
import { DEFAULT_REPLY_MAX_CHARS } from "./constants.js";
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
function sanitizeVisibleText(value) {
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
function buildStableSessionId(sessionKey) {
    const hash = createHash("sha1").update(sessionKey).digest("hex");
    return `agentschatapp-${hash.slice(0, 24)}`;
}
function asRecord(value) {
    return value != null && typeof value === "object" ? value : {};
}
function normalizeOptionalString(value) {
    if (typeof value !== "string") {
        return undefined;
    }
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : undefined;
}
function resolvePrimaryModelSelection(value) {
    if (typeof value === "string") {
        return normalizeOptionalString(value);
    }
    return normalizeOptionalString(asRecord(value).primary);
}
function resolveUniqueProviderForModel(cfg, model) {
    const providers = asRecord(cfg.models?.providers);
    const matches = Object.entries(providers).flatMap(([providerId, providerConfig]) => {
        const models = Array.isArray(asRecord(providerConfig).models)
            ? asRecord(providerConfig).models
            : [];
        return models.some((entry) => normalizeOptionalString(asRecord(entry).id) === model) ? [providerId] : [];
    });
    return matches.length === 1 ? matches[0] : undefined;
}
function splitModelSelection(cfg, modelSelection, fallbackProvider) {
    const trimmed = modelSelection.trim();
    const separatorIndex = trimmed.indexOf("/");
    if (separatorIndex > 0 && separatorIndex < trimmed.length - 1) {
        return {
            provider: trimmed.slice(0, separatorIndex).trim(),
            model: trimmed.slice(separatorIndex + 1).trim()
        };
    }
    return {
        provider: resolveUniqueProviderForModel(cfg, trimmed) ?? fallbackProvider,
        model: trimmed
    };
}
function resolveEmbeddedModelSelection(cfg, agentId, fallbackProvider, fallbackModel) {
    const agentConfig = Array.isArray(cfg.agents?.list)
        ? cfg.agents.list.find((entry) => normalizeOptionalString(asRecord(entry).id) === agentId)
        : undefined;
    const selectedModel = resolvePrimaryModelSelection(asRecord(agentConfig).model)
        ?? resolvePrimaryModelSelection(cfg.agents?.defaults?.model)
        ?? `${fallbackProvider}/${fallbackModel}`;
    return splitModelSelection(cfg, selectedModel, fallbackProvider);
}
export function buildSessionKey(account, kind, threadId) {
    if (kind === "dm") {
        return `agentschatapp:${account.openclawAgent}:${threadId}`;
    }
    return `agentschatapp:${account.openclawAgent}:${kind}:${threadId}`;
}
export async function runEmbeddedReply(context, params) {
    const cfg = context.runtime.config.loadConfig();
    const sessionKey = buildSessionKey(params.account, params.kind, params.threadId);
    const sessionId = buildStableSessionId(sessionKey);
    const agentDir = context.runtime.agent.resolveAgentDir(cfg, params.account.openclawAgent);
    const workspaceDir = context.runtime.agent.resolveAgentWorkspaceDir(cfg, params.account.openclawAgent);
    const modelSelection = resolveEmbeddedModelSelection(cfg, params.account.openclawAgent, context.runtime.agent.defaults.provider, context.runtime.agent.defaults.model);
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
        agentDir,
        config: cfg,
        sessionFile,
        workspaceDir,
        prompt: params.prompt,
        provider: modelSelection.provider,
        model: modelSelection.model,
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
    const output = trimReplyText(sanitizeVisibleText(resolveFinalVisibleText(result)), params.maxChars ?? DEFAULT_REPLY_MAX_CHARS);
    if (output.length === 0) {
        throw new Error("OpenClaw embedded run returned no visible text.");
    }
    return output;
}
