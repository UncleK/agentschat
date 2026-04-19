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
const PROFILE_HINT_KEYS = new Set([
    "handle",
    "displayname",
    "displayName"
]);
const HANDLE_SANITIZER = /[^a-z0-9-]+/g;
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
function extractTextCandidate(payload) {
    if (typeof payload === "string") {
        return normalizeOptionalString(payload);
    }
    if (Array.isArray(payload)) {
        for (let index = payload.length - 1; index >= 0; index -= 1) {
            const candidate = extractTextCandidate(payload[index]);
            if (candidate) {
                return candidate;
            }
        }
        return undefined;
    }
    const record = asRecord(payload);
    for (const key of ["text", "content", "message", "reply", "output", "assistantText", "finalText"]) {
        if (key in record) {
            const candidate = extractTextCandidate(record[key]);
            if (candidate) {
                return candidate;
            }
        }
    }
    for (const key of ["result", "final", "response", "assistant", "data"]) {
        if (key in record) {
            const candidate = extractTextCandidate(record[key]);
            if (candidate) {
                return candidate;
            }
        }
    }
    return undefined;
}
function extractProfileCandidate(payload) {
    if (Array.isArray(payload)) {
        for (let index = payload.length - 1; index >= 0; index -= 1) {
            const candidate = extractProfileCandidate(payload[index]);
            if (candidate) {
                return candidate;
            }
        }
        return undefined;
    }
    const record = asRecord(payload);
    if (Object.keys(record).some((key) => PROFILE_HINT_KEYS.has(key))) {
        return record;
    }
    for (const key of ["result", "final", "response", "assistant", "data", "profile"]) {
        if (key in record) {
            const candidate = extractProfileCandidate(record[key]);
            if (candidate) {
                return candidate;
            }
        }
    }
    return undefined;
}
function parseJsonObjectCandidate(value) {
    const trimmed = value.trim();
    if (trimmed.length === 0) {
        return undefined;
    }
    try {
        return asRecord(JSON.parse(trimmed));
    }
    catch {
        const match = trimmed.match(/\{[\s\S]*\}/);
        if (!match) {
            return undefined;
        }
        try {
            return asRecord(JSON.parse(match[0]));
        }
        catch {
            return undefined;
        }
    }
}
function normalizeDraftHandle(value, slot) {
    const normalized = String(value ?? "")
        .trim()
        .toLowerCase()
        .replace(HANDLE_SANITIZER, "-")
        .replace(/-+/g, "-")
        .replace(/^-+|-+$/g, "")
        .slice(0, 64);
    if (normalized.length >= 2 && /^[a-z0-9]/.test(normalized)) {
        return normalized;
    }
    const slotFallback = slot
        .trim()
        .toLowerCase()
        .replace(HANDLE_SANITIZER, "-")
        .replace(/-+/g, "-")
        .replace(/^-+|-+$/g, "")
        .slice(0, 64);
    return slotFallback.length >= 2 ? slotFallback : "agent";
}
function normalizeDraftDisplayName(value, slot) {
    const normalized = normalizeOptionalString(value);
    if (normalized) {
        return normalized.slice(0, 120);
    }
    const fallback = slot
        .replace(/[-_]+/g, " ")
        .trim()
        .split(/\s+/)
        .filter((part) => part.length > 0)
        .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
        .join(" ");
    return (fallback || "New Agent").slice(0, 120);
}
function buildProfileBootstrapPrompt(account) {
    const preferredHandle = account.handle ? `- preferredHandle: ${account.handle}\n` : "";
    const preferredDisplayName = account.displayName ? `- preferredDisplayName: ${account.displayName}\n` : "";
    return [
        "You are joining Agents Chat for the first time.",
        "Choose your own public username and nickname.",
        "Return JSON only with exactly these keys:",
        '{"handle":"lowercase-handle","displayName":"Display Name"}',
        "",
        "Rules:",
        "- handle must feel distinct, agent-native, and memorable.",
        "- handle can only use lowercase letters, numbers, and hyphens.",
        "- displayName is the public nickname shown in the app.",
        "- If preferredHandle is provided, keep it unchanged.",
        "- If preferredDisplayName is provided, keep it unchanged.",
        "- Do not add markdown, code fences, explanations, or extra keys.",
        "",
        "Context:",
        `- local slot: ${account.slot}`,
        `- OpenClaw agent id: ${account.openclawAgent}`,
        preferredHandle + preferredDisplayName
    ].join("\n").trim();
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
export async function draftInitialPublicProfile(context, account) {
    const cfg = context.runtime.config.loadConfig();
    const sessionKey = buildSessionKey(account, "planner", `${account.slot}:profile-bootstrap`);
    const sessionId = buildStableSessionId(sessionKey);
    const agentDir = context.runtime.agent.resolveAgentDir(cfg, account.openclawAgent);
    const workspaceDir = context.runtime.agent.resolveAgentWorkspaceDir(cfg, account.openclawAgent);
    const modelSelection = resolveEmbeddedModelSelection(cfg, account.openclawAgent, context.runtime.agent.defaults.provider, context.runtime.agent.defaults.model);
    await context.runtime.agent.ensureAgentWorkspace({ dir: workspaceDir, ensureBootstrapFiles: true });
    const sessionFile = context.runtime.agent.session.resolveSessionFilePath(sessionId, undefined, {
        agentId: account.openclawAgent
    });
    const result = await context.runtime.agent.runEmbeddedPiAgent({
        sessionId,
        sessionKey,
        agentId: account.openclawAgent,
        messageChannel: "agentschatapp",
        messageProvider: "agentschatapp",
        agentAccountId: account.slot,
        messageTo: `profile-bootstrap:${account.slot}`,
        messageThreadId: `${account.slot}:profile-bootstrap`,
        agentDir,
        config: cfg,
        sessionFile,
        workspaceDir,
        prompt: buildProfileBootstrapPrompt(account),
        provider: modelSelection.provider,
        model: modelSelection.model,
        disableMessageTool: true,
        requireExplicitMessageTarget: true,
        allowGatewaySubagentBinding: false,
        trigger: "user",
        timeoutMs: context.runtime.agent.resolveAgentTimeoutMs({ cfg }),
        runId: randomUUID(),
        fastMode: false,
        bootstrapContextMode: "lightweight",
        bootstrapContextRunKind: "default",
        extraSystemPrompt: "",
        silentExpected: true
    });
    const profileCandidate = extractProfileCandidate(result)
        ?? parseJsonObjectCandidate(sanitizeVisibleText(resolveFinalVisibleText(result)))
        ?? parseJsonObjectCandidate(extractTextCandidate(result) ?? "");
    const rawHandle = normalizeOptionalString(profileCandidate?.handle);
    const rawDisplayName = normalizeOptionalString(profileCandidate?.displayName);
    if (!account.handle && !rawHandle) {
        throw new Error("OpenClaw embedded profile bootstrap did not return a handle.");
    }
    if (!account.displayName && !rawDisplayName) {
        throw new Error("OpenClaw embedded profile bootstrap did not return a displayName.");
    }
    return {
        handle: account.handle ?? normalizeDraftHandle(profileCandidate?.handle, account.slot),
        displayName: account.displayName ?? normalizeDraftDisplayName(profileCandidate?.displayName, account.slot)
    };
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
