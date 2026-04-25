import { buildSessionKey, runEmbeddedReply } from "./embedded.js";
import { readDebate, readDmThreadMessages, readForumTopic } from "./launcher.js";
import { buildDmDecisionPrompt, buildDreamPrompt, buildForumDecisionPrompt, buildInitialPersonalityPrompt, buildLiveDecisionPrompt } from "./prompts.js";
import { activityPenaltyMultiplier, buildFallbackPersonalitySummary, clampTraitDrift, clonePersonality, computeReplyThreshold, diffPersonalityTraits, normalizePersonality, personalityToPayload, randomDebounceMs, resolveStatePersonality } from "./personality.js";
import { countRecentThreadReplies, loadReflectionMemory, recordReflectionInteraction, saveReflectionMemory, wasTraitChangedRecently } from "./reflection-memory.js";
import { wait } from "./http.js";
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
function normalizeActorType(value) {
    return typeof value === "string" ? value.trim().toLowerCase() : "";
}
function normalizeMessageContent(message) {
    const content = normalizeOptionalString(message.content);
    if (content) {
        return content;
    }
    return normalizeOptionalString(message.contentType) ?? "";
}
function parseIsoMs(value) {
    if (typeof value !== "string" || value.trim().length === 0) {
        return null;
    }
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
}
function clamp(min, value, max) {
    return Math.max(min, Math.min(max, value));
}
function trimText(value, maxLength) {
    const normalized = value.trim();
    if (normalized.length <= maxLength) {
        return normalized;
    }
    if (maxLength <= 3) {
        return normalized.slice(0, maxLength);
    }
    return `${normalized.slice(0, maxLength - 3).trimEnd()}...`;
}
function normalizeReplyMode(value) {
    return value === "audio" ? "audio" : "text";
}
function detectLowSignal(content) {
    const normalized = content.trim().toLowerCase();
    if (normalized.length === 0) {
        return true;
    }
    if (/^:[a-z0-9_+-]+:$/.test(normalized)) {
        return true;
    }
    if (/^(ok|okay|k|kk|lol|hi|hey|yo|nice|cool|sure|thanks|thx|收到|好的|嗯嗯)$/i.test(normalized)) {
        return true;
    }
    return normalized.length < 8 && !normalized.includes("?") && !normalized.includes("？");
}
function mentionsAgent(content, state) {
    const normalized = content.toLowerCase();
    const candidates = [
        state.displayName?.toLowerCase(),
        state.agentHandle?.toLowerCase(),
        state.agentHandle ? `@${state.agentHandle.toLowerCase()}` : undefined
    ].filter((entry) => Boolean(entry && entry.trim().length > 0));
    return candidates.some((entry) => normalized.includes(entry));
}
function hasQuestion(content) {
    return content.includes("?") || content.includes("？");
}
function hasHelpSignal(content) {
    return /\b(help|why|how|should|could|can you|need|stuck|issue|problem|debate|disagree)\b/i.test(content)
        || /帮|请问|为什么|如何|问题|需要|卡住|辩论|不同意/.test(content);
}
function limitMessages(messages, maxCount, maxChars) {
    const filtered = messages.slice(-maxCount);
    const selected = [];
    let remainingChars = maxChars;
    for (let index = filtered.length - 1; index >= 0; index -= 1) {
        const message = filtered[index];
        const content = normalizeMessageContent(message);
        const cost = Math.max(content.length, 1);
        if (selected.length > 0 && remainingChars - cost < 0) {
            break;
        }
        remainingChars -= cost;
        selected.push(message);
    }
    return selected.reverse();
}
function limitTopicReplies(topic, maxTopLevelReplies) {
    const replies = Array.isArray(topic.replies) ? topic.replies : [];
    return {
        ...topic,
        replies: replies.slice(-maxTopLevelReplies)
    };
}
function limitDebatePayload(debate) {
    return {
        ...debate,
        formalTurns: Array.isArray(debate.formalTurns) ? debate.formalTurns.slice(-6) : [],
        spectatorFeed: Array.isArray(debate.spectatorFeed) ? debate.spectatorFeed.slice(-6) : []
    };
}
function parseDecisionEnvelope(rawText) {
    const normalized = rawText.trim();
    if (normalized.length === 0 || normalized.toUpperCase() === "NO_REPLY") {
        return {
            decision: "skip",
            reasonTag: "not_interesting",
            replyMode: "text",
            replyText: ""
        };
    }
    const match = normalized.match(/\{[\s\S]*\}/);
    let parsed = {};
    if (match) {
        try {
            parsed = asRecord(JSON.parse(match[0]));
        }
        catch {
            parsed = {};
        }
    }
    const decision = parsed.decision === "reply" ? "reply" : parsed.decision === "skip" ? "skip" : undefined;
    const reasonTag = parsed.reasonTag;
    if (decision && (reasonTag === "addressed"
        || reasonTag === "useful"
        || reasonTag === "novelty"
        || reasonTag === "low_signal"
        || reasonTag === "already_answered"
        || reasonTag === "cooldown"
        || reasonTag === "unsafe"
        || reasonTag === "not_interesting")) {
        return {
            decision,
            reasonTag,
            replyMode: decision === "reply" ? normalizeReplyMode(parsed.replyMode) : "text",
            replyText: decision === "reply" ? trimText(normalizeOptionalString(parsed.replyText) ?? "", 4000) : ""
        };
    }
    return {
        decision: "reply",
        reasonTag: "useful",
        replyMode: "text",
        replyText: trimText(normalized, 4000)
    };
}
function newerExternalActivityExists(params) {
    if (params.sinceMs == null) {
        return false;
    }
    const sinceMs = params.sinceMs;
    return params.entries.some((entry) => {
        const actor = params.actorResolver(entry);
        if (actor.occurredAtMs == null || actor.occurredAtMs <= sinceMs) {
            return false;
        }
        if (actor.actorType === "agent" && actor.actorId === params.selfAgentId) {
            return false;
        }
        if (params.originalActorId && actor.actorId === params.originalActorId) {
            return false;
        }
        return true;
    });
}
function buildInteractionSummary(params) {
    const sender = params.senderName?.trim() || "someone";
    const content = trimText(params.content, 96) || "[empty]";
    const verb = params.outcome === "reply" ? "Replied to" : "Skipped";
    return `${verb} ${params.surface} from ${sender}: ${content} (${params.reasonTag}).`;
}
function interestScoreForEvent(params) {
    const lowSignal = detectLowSignal(params.content);
    const recentOwnReplies = countRecentThreadReplies(params.memory, params.threadKey, 15 * 60 * 1000);
    let score = 0;
    if (params.surface === "dm") {
        score += 2;
    }
    if (mentionsAgent(params.content, params.state)) {
        score += 4;
    }
    if (hasQuestion(params.content)) {
        score += 3;
    }
    if (hasHelpSignal(params.content)) {
        score += 2;
    }
    if (params.content.trim().length >= 24) {
        score += 1;
    }
    if (lowSignal) {
        score -= 3;
    }
    if (params.alreadyAnswered) {
        score -= 4;
    }
    if (recentOwnReplies > 0) {
        const penalty = Math.ceil(recentOwnReplies * activityPenaltyMultiplier(params.activityLevel));
        score -= penalty;
    }
    return {
        score: clamp(-5, score, 7),
        lowSignal,
        recentOwnReplies
    };
}
async function syncPersonalityToServer(state, personality, submitAndWaitForSuccess, idempotencyKey) {
    await submitAndWaitForSuccess(state, {
        type: "agent.profile.update",
        payload: {
            personality: personalityToPayload(personality)
        }
    }, idempotencyKey);
    state.personality = clonePersonality(personality);
}
export async function ensurePersonalityInitialized(params) {
    if (params.state.personality) {
        return resolveStatePersonality(params.state);
    }
    const fallback = normalizePersonality({
        summary: buildFallbackPersonalitySummary({
            displayName: params.state.displayName ?? params.account.displayName,
            bio: params.state.bio ?? params.account.bio,
            profileTags: params.state.profileTags ?? params.account.profileTags
        }),
        autoEvolve: true
    });
    let nextPersonality = fallback;
    try {
        const draft = await runEmbeddedReply(params.context, {
            account: params.account,
            kind: "planner",
            threadId: `${params.account.slot}:personality-bootstrap`,
            prompt: buildInitialPersonalityPrompt({
                displayName: params.state.displayName ?? params.account.displayName,
                bio: params.state.bio ?? params.account.bio,
                tags: params.state.profileTags ?? params.account.profileTags
            }),
            maxChars: 1000
        });
        nextPersonality = normalizePersonality(JSON.parse(draft), fallback);
    }
    catch (error) {
        params.logger.warn(`Agents Chat slot '${params.account.slot}' could not draft initial personality, using fallback: ${error instanceof Error ? error.message : String(error)}`);
    }
    await syncPersonalityToServer(params.state, nextPersonality, params.submitAndWaitForSuccess, `agentschatapp-personality-bootstrap-${params.account.slot}`);
    return nextPersonality;
}
export async function maybeRunDailyDream(params) {
    const personality = params.state.personality ? resolveStatePersonality(params.state) : null;
    if (!personality || !personality.autoEvolve) {
        return;
    }
    const memory = loadReflectionMemory(params.account.slot, params.context.stateStore);
    const lastDreamedAtMs = personality.lastDreamedAt ? Date.parse(personality.lastDreamedAt) : Number.NaN;
    if (!Number.isNaN(lastDreamedAtMs) && (Date.now() - lastDreamedAtMs) < 24 * 60 * 60 * 1000) {
        return;
    }
    if (memory.interactionCounters.considered7d < 20) {
        return;
    }
    const fallback = clonePersonality(personality);
    fallback.lastDreamedAt = new Date().toISOString();
    let dreamed = fallback;
    try {
        const draft = await runEmbeddedReply(params.context, {
            account: params.account,
            kind: "planner",
            threadId: `${params.account.slot}:personality-dream`,
            prompt: buildDreamPrompt({
                personality,
                rollingSummary7d: memory.rollingSummary7d,
                dailyDigests: memory.dailyDigests.map((digest) => {
                    const highlights = digest.highlights.length > 0 ? ` Highlights: ${digest.highlights.join(" | ")}` : "";
                    return `- ${digest.day}: considered ${digest.consideredCount}, replied ${digest.repliedCount}, skipped ${digest.skippedCount}.${highlights}`;
                })
            }),
            maxChars: 1000
        });
        dreamed = normalizePersonality(JSON.parse(draft), fallback);
    }
    catch (error) {
        params.logger.warn(`Agents Chat slot '${params.account.slot}' could not complete one dream cycle, keeping personality stable: ${error instanceof Error ? error.message : String(error)}`);
    }
    dreamed.autoEvolve = true;
    const dreamedAt = new Date().toISOString();
    dreamed.lastDreamedAt = dreamedAt;
    dreamed = clampTraitDrift(personality, dreamed);
    const changedTraits = diffPersonalityTraits(personality, dreamed);
    if (changedTraits.length > 1) {
        for (const trait of changedTraits.slice(1)) {
            dreamed[trait] = personality[trait];
        }
    }
    const primaryTrait = diffPersonalityTraits(personality, dreamed)[0];
    if (primaryTrait && wasTraitChangedRecently(memory, primaryTrait, 72 * 60 * 60 * 1000)) {
        dreamed[primaryTrait] = personality[primaryTrait];
    }
    memory.lastDreamedAt = dreamedAt;
    if (primaryTrait && personality[primaryTrait] !== dreamed[primaryTrait]) {
        memory.pendingTraitDrift = {
            trait: primaryTrait,
            from: String(personality[primaryTrait]),
            to: String(dreamed[primaryTrait]),
            at: dreamedAt
        };
    }
    else {
        memory.pendingTraitDrift = null;
    }
    memory.lastPersonalitySnapshot = clonePersonality(dreamed);
    saveReflectionMemory(params.account.slot, params.context.stateStore, memory);
    await syncPersonalityToServer(params.state, dreamed, params.submitAndWaitForSuccess, `agentschatapp-personality-dream-${params.account.slot}-${dreamed.lastDreamedAt}`);
}
async function recordDecision(params) {
    const memory = loadReflectionMemory(params.account.slot, params.context.stateStore);
    const updated = recordReflectionInteraction(memory, {
        at: new Date().toISOString(),
        surface: params.surface,
        threadKey: params.threadKey,
        outcome: params.outcome,
        reasonTag: params.reasonTag,
        summary: buildInteractionSummary({
            surface: params.surface,
            outcome: params.outcome,
            senderName: params.senderName,
            content: params.content,
            reasonTag: params.reasonTag
        })
    });
    saveReflectionMemory(params.account.slot, params.context.stateStore, updated);
}
async function maybeDelay(surface, personality, abortSignal) {
    await wait(randomDebounceMs(surface, personality), abortSignal);
}
export async function decideDmReply(params) {
    const event = asRecord(params.delivery.event);
    const threadId = normalizeOptionalString(event.threadId) ?? "";
    const personality = resolveStatePersonality(params.state);
    await maybeDelay("dm", personality, params.abortSignal);
    const response = await readDmThreadMessages(params.state.serverBaseUrl, params.state.accessToken, threadId);
    const messages = limitMessages(Array.isArray(response.messages) ? response.messages.filter((entry) => entry != null && typeof entry === "object") : [], 12, 3000);
    const content = normalizeOptionalString(event.content) ?? normalizeOptionalString(event.contentType) ?? "";
    const originalActorId = normalizeOptionalString(event.actorAgentId ?? event.actorUserId);
    const alreadyAnswered = newerExternalActivityExists({
        selfAgentId: params.state.agentId ?? "",
        originalActorId,
        sinceMs: parseIsoMs(event.occurredAt),
        entries: messages,
        actorResolver: (message) => {
            const actor = asRecord(message.actor);
            return {
                actorId: normalizeOptionalString(actor.id),
                actorType: normalizeActorType(actor.type),
                occurredAtMs: parseIsoMs(message.occurredAt)
            };
        }
    });
    const memory = loadReflectionMemory(params.account.slot, params.context.stateStore);
    const threadKey = buildSessionKey(params.account, "dm", threadId);
    const score = interestScoreForEvent({
        surface: "dm",
        content,
        state: params.state,
        activityLevel: params.activityLevel,
        memory,
        threadKey,
        alreadyAnswered
    });
    const threshold = computeReplyThreshold(params.activityLevel, personality);
    if (score.score < threshold) {
        const reasonTag = alreadyAnswered
            ? "already_answered"
            : score.lowSignal
                ? "low_signal"
                : score.recentOwnReplies > 0
                    ? "cooldown"
                    : "not_interesting";
        await recordDecision({
            context: params.context,
            account: params.account,
            threadKey,
            surface: "dm",
            content,
            senderName: normalizeOptionalString(event.actorDisplayName) ?? null,
            outcome: "skip",
            reasonTag
        });
        return { decision: "skip", reasonTag, replyMode: "text", replyText: "" };
    }
    const rawDecision = await runEmbeddedReply(params.context, {
        account: params.account,
        kind: "dm",
        threadId,
        senderId: originalActorId ?? null,
        senderName: normalizeOptionalString(event.actorDisplayName) ?? null,
        senderUsername: normalizeOptionalString(event.actorHandle) ?? null,
        prompt: buildDmDecisionPrompt({
            selfAgentId: params.state.agentId ?? "",
            delivery: params.delivery,
            messages,
            activityLevel: params.activityLevel,
            personality,
            interestScore: score.score,
            replyThreshold: threshold,
            recentOwnReplies: score.recentOwnReplies,
            alreadyAnswered
        })
    });
    const decision = parseDecisionEnvelope(rawDecision);
    await recordDecision({
        context: params.context,
        account: params.account,
        threadKey,
        surface: "dm",
        content,
        senderName: normalizeOptionalString(event.actorDisplayName) ?? null,
        outcome: decision.decision,
        reasonTag: decision.reasonTag
    });
    return decision;
}
export async function decideForumReply(params) {
    const event = asRecord(params.delivery.event);
    const threadId = normalizeOptionalString(event.threadId) ?? "";
    const personality = resolveStatePersonality(params.state);
    await maybeDelay("forum", personality, params.abortSignal);
    const response = await readForumTopic(params.state.serverBaseUrl, params.state.accessToken, threadId);
    const topic = limitTopicReplies(asRecord(response.topic), 6);
    const content = normalizeOptionalString(event.content) ?? "";
    const originalActorId = normalizeOptionalString(event.actorAgentId ?? event.actorUserId);
    const replies = Array.isArray(topic.replies) ? topic.replies : [];
    const alreadyAnswered = newerExternalActivityExists({
        selfAgentId: params.state.agentId ?? "",
        originalActorId,
        sinceMs: parseIsoMs(event.occurredAt),
        entries: replies,
        actorResolver: (reply) => ({
            actorId: normalizeOptionalString(reply.authorId ?? reply.authorAgentId ?? reply.authorUserId),
            actorType: normalizeActorType(reply.authorType),
            occurredAtMs: parseIsoMs(reply.createdAt ?? reply.occurredAt)
        })
    });
    const memory = loadReflectionMemory(params.account.slot, params.context.stateStore);
    const threadKey = buildSessionKey(params.account, "forum", threadId);
    const score = interestScoreForEvent({
        surface: "forum",
        content,
        state: params.state,
        activityLevel: params.activityLevel,
        memory,
        threadKey,
        alreadyAnswered
    });
    const threshold = computeReplyThreshold(params.activityLevel, personality);
    if (score.score < threshold) {
        const reasonTag = alreadyAnswered
            ? "already_answered"
            : score.lowSignal
                ? "low_signal"
                : score.recentOwnReplies > 0
                    ? "cooldown"
                    : "not_interesting";
        await recordDecision({
            context: params.context,
            account: params.account,
            threadKey,
            surface: "forum",
            content,
            senderName: normalizeOptionalString(event.actorDisplayName) ?? null,
            outcome: "skip",
            reasonTag
        });
        return { decision: { decision: "skip", reasonTag, replyMode: "text", replyText: "" }, topic };
    }
    const rawDecision = await runEmbeddedReply(params.context, {
        account: params.account,
        kind: "forum",
        threadId,
        senderId: originalActorId ?? null,
        senderName: normalizeOptionalString(event.actorDisplayName) ?? null,
        prompt: buildForumDecisionPrompt({
            delivery: params.delivery,
            topic,
            activityLevel: params.activityLevel,
            personality,
            interestScore: score.score,
            replyThreshold: threshold,
            recentOwnReplies: score.recentOwnReplies,
            alreadyAnswered
        })
    });
    const decision = parseDecisionEnvelope(rawDecision);
    await recordDecision({
        context: params.context,
        account: params.account,
        threadKey,
        surface: "forum",
        content,
        senderName: normalizeOptionalString(event.actorDisplayName) ?? null,
        outcome: decision.decision,
        reasonTag: decision.reasonTag
    });
    return { decision, topic };
}
export async function decideLiveReply(params) {
    const event = asRecord(params.delivery.event);
    const debateSessionId = normalizeOptionalString(event.targetId) ?? "";
    const personality = resolveStatePersonality(params.state);
    await maybeDelay("live", personality, params.abortSignal);
    const debateResponse = asRecord(await readDebate(params.state.serverBaseUrl, debateSessionId));
    const debate = limitDebatePayload(typeof debateResponse.debateSessionId === "string"
        ? debateResponse
        : asRecord(debateResponse.session));
    const content = normalizeOptionalString(event.content) ?? "";
    const originalActorId = normalizeOptionalString(event.actorAgentId ?? event.actorUserId);
    const spectatorFeed = Array.isArray(debate.spectatorFeed) ? debate.spectatorFeed : [];
    const alreadyAnswered = newerExternalActivityExists({
        selfAgentId: params.state.agentId ?? "",
        originalActorId,
        sinceMs: parseIsoMs(event.occurredAt),
        entries: spectatorFeed,
        actorResolver: (entry) => ({
            actorId: normalizeOptionalString(entry.actorId ?? entry.actorAgentId ?? entry.actorUserId),
            actorType: normalizeActorType(entry.actorType),
            occurredAtMs: parseIsoMs(entry.occurredAt)
        })
    });
    const memory = loadReflectionMemory(params.account.slot, params.context.stateStore);
    const threadKey = buildSessionKey(params.account, "live", debateSessionId);
    const score = interestScoreForEvent({
        surface: "live",
        content,
        state: params.state,
        activityLevel: params.activityLevel,
        memory,
        threadKey,
        alreadyAnswered
    });
    const threshold = computeReplyThreshold(params.activityLevel, personality);
    if (score.score < threshold) {
        const reasonTag = alreadyAnswered
            ? "already_answered"
            : score.lowSignal
                ? "low_signal"
                : score.recentOwnReplies > 0
                    ? "cooldown"
                    : "not_interesting";
        await recordDecision({
            context: params.context,
            account: params.account,
            threadKey,
            surface: "live",
            content,
            senderName: normalizeOptionalString(event.actorDisplayName) ?? null,
            outcome: "skip",
            reasonTag
        });
        return { decision: { decision: "skip", reasonTag, replyMode: "text", replyText: "" }, debate };
    }
    const rawDecision = await runEmbeddedReply(params.context, {
        account: params.account,
        kind: "live",
        threadId: debateSessionId,
        senderId: originalActorId ?? null,
        senderName: normalizeOptionalString(event.actorDisplayName) ?? null,
        prompt: buildLiveDecisionPrompt({
            delivery: params.delivery,
            debate,
            activityLevel: params.activityLevel,
            personality,
            interestScore: score.score,
            replyThreshold: threshold,
            recentOwnReplies: score.recentOwnReplies,
            alreadyAnswered
        })
    });
    const decision = parseDecisionEnvelope(rawDecision);
    await recordDecision({
        context: params.context,
        account: params.account,
        threadKey,
        surface: "live",
        content,
        senderName: normalizeOptionalString(event.actorDisplayName) ?? null,
        outcome: decision.decision,
        reasonTag: decision.reasonTag
    });
    return { decision, debate };
}
