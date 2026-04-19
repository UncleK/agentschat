import { DEFAULT_MANAGER_INTERVAL_MS, DEFAULT_POLL_BACKOFF_SECONDS, DEFAULT_POLL_WAIT_SECONDS, DEFAULT_SAFETY_POLICY_REFRESH_MS } from "./constants.js";
import { buildSessionKey, runEmbeddedReply } from "./embedded.js";
import { buildDebatePrompt, buildDebateSpectatorPrompt, buildDmPrompt, buildForumPrompt, isNoReply } from "./prompts.js";
import { maybeRunHighActivityDiscovery } from "./worker-discovery.js";
import { accountFingerprint, isConfiguredAgentsChatAccount, listAgentsChatAccounts } from "./config.js";
import { ackDeliveries, AgentsChatConnectionStateError, connectAccount, pollDeliveries, readDebate, readDmThreadMessages, readForumTopic, readSafetyPolicy, submitAction, waitForActionCompletion } from "./launcher.js";
import { AgentsChatHttpError, AgentsChatNetworkError, wait } from "./http.js";
import { clearSlotState, loadSlotState, saveSlotState } from "./state.js";
let managerTimer = null;
let managerContext = null;
let managerLogger = null;
let managerReconcilePromise = null;
const activeWorkers = new Map();
const workerRuntimeState = new Map();
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
function nowIso() {
    return new Date().toISOString();
}
function nowMs() {
    return Date.now();
}
function parseIsoMs(value) {
    if (!value) {
        return null;
    }
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
}
function fallbackSafetyPolicy(state) {
    return state.safetyPolicy ?? {
        dmPolicyMode: "followers_only",
        requiresMutualFollowForDm: false,
        allowProactiveInteractions: true,
        activityLevel: "normal"
    };
}
function effectiveActivityLevel(policy) {
    if (!policy.allowProactiveInteractions) {
        return "low";
    }
    return policy.activityLevel;
}
function normalizeActorType(value) {
    return typeof value === "string" ? value.trim().toLowerCase() : "";
}
function isHumanActor(event) {
    return normalizeActorType(event.actorType) === "human";
}
function isSelfAgentActor(event, state) {
    return normalizeActorType(event.actorType) === "agent"
        && typeof event.actorAgentId === "string"
        && event.actorAgentId === state.agentId;
}
function allowsSurfaceReplies(activityLevel, surface) {
    if (surface === "dm") {
        return true;
    }
    return activityLevel === "normal" || activityLevel === "high";
}
function allowsHumanConversation(activityLevel, surface) {
    if (surface === "dm") {
        return activityLevel === "normal" || activityLevel === "high";
    }
    return activityLevel === "high";
}
function shouldIgnoreForHumanConversationGate(event, activityLevel, surface) {
    return isHumanActor(event) && !allowsHumanConversation(activityLevel, surface);
}
function unwrapDebate(payload) {
    if (typeof payload.debateSessionId === "string") {
        return payload;
    }
    const session = payload.session;
    if (session != null && typeof session === "object") {
        return session;
    }
    throw new Error("Debate response is missing session data.");
}
function deriveReplyTarget(event) {
    if (event.actorType === "agent" && typeof event.actorAgentId === "string" && event.actorAgentId.length > 0) {
        return { targetType: "agent", targetId: event.actorAgentId };
    }
    if (event.actorType === "human" && typeof event.actorUserId === "string" && event.actorUserId.length > 0) {
        return { targetType: "human", targetId: event.actorUserId };
    }
    throw new Error("Unable to derive DM target from delivery actor.");
}
function extractMessages(payload) {
    const messages = Array.isArray(payload.messages) ? payload.messages : [];
    return messages.filter((message) => message != null && typeof message === "object");
}
function extractDeliveries(payload) {
    const deliveries = Array.isArray(payload.deliveries) ? payload.deliveries : [];
    return deliveries.filter((delivery) => delivery != null && typeof delivery === "object");
}
function ensureWorkerState(slot) {
    const existing = workerRuntimeState.get(slot);
    if (existing) {
        return existing;
    }
    const fresh = {
        slot,
        running: false,
        connected: false,
        reconnectAttempts: 0,
        lastError: null,
        degradedReason: null,
        conflictState: null,
        healthState: "idle",
        nextDiscoveryAt: null
    };
    workerRuntimeState.set(slot, fresh);
    return fresh;
}
function syncRuntimeFromState(runtimeState, state) {
    runtimeState.agentId = state.agentId;
    runtimeState.lastConnectedAt = parseIsoMs(state.lastConnectedAt);
    runtimeState.lastInboundAt = parseIsoMs(state.lastInboundAt);
    runtimeState.lastOutboundAt = parseIsoMs(state.lastOutboundAt);
    runtimeState.lastPolicySyncAt = parseIsoMs(state.lastPolicySyncAt);
    runtimeState.lastDiscoveryAt = parseIsoMs(state.lastDiscoveryAt);
    runtimeState.lastProactiveActionAt = parseIsoMs(state.lastProactiveActionAt);
    runtimeState.lastProactiveActionType = state.lastProactiveActionType ?? null;
    runtimeState.lastError = state.lastError ?? null;
    runtimeState.degradedReason = state.degradedReason ?? null;
    runtimeState.conflictState = state.conflictState ?? null;
}
function persistState(context, slot, state, runtimeState) {
    saveSlotState(slot, state, context.stateStore);
    if (runtimeState) {
        syncRuntimeFromState(runtimeState, state);
    }
}
async function submitAndWaitForSuccess(state, action, idempotencyKey) {
    if (!state.serverBaseUrl || !state.accessToken) {
        throw new Error("Slot is missing serverBaseUrl or accessToken.");
    }
    const submitted = await submitAction(state.serverBaseUrl, state.accessToken, action, idempotencyKey);
    const actionId = normalizeOptionalString(submitted.id);
    if (!actionId) {
        throw new Error(`${action.type} did not return an action id.`);
    }
    const completion = await waitForActionCompletion(state.serverBaseUrl, state.accessToken, actionId);
    if (completion.status !== "succeeded") {
        throw new Error(`${action.type} failed: ${JSON.stringify(completion)}`);
    }
    state.lastOutboundAt = nowIso();
    return asRecord(completion.result);
}
async function loadSafetyPolicy(state, logger, force = false) {
    if (!state.serverBaseUrl || !state.accessToken) {
        return fallbackSafetyPolicy(state);
    }
    const cached = state.safetyPolicy;
    const fetchedAt = state.safetyPolicyFetchedAtUnixMs ?? 0;
    if (!force && cached && nowMs() - fetchedAt < DEFAULT_SAFETY_POLICY_REFRESH_MS) {
        return cached;
    }
    try {
        const policy = await readSafetyPolicy(state.serverBaseUrl, state.accessToken);
        state.safetyPolicy = policy;
        state.safetyPolicyFetchedAtUnixMs = nowMs();
        state.lastPolicySyncAt = nowIso();
        state.degradedReason = null;
        return policy;
    }
    catch (error) {
        if (error instanceof AgentsChatHttpError && error.statusCode === 401) {
            throw error;
        }
        logger.warn(`Agents Chat slot '${state.agentSlotId}' could not refresh safety policy, reusing cached value: ${error instanceof Error ? error.message : String(error)}`);
        return fallbackSafetyPolicy(state);
    }
}
async function processDmDelivery(context, account, state, delivery, safetyPolicy) {
    const event = asRecord(delivery.event);
    const threadId = normalizeOptionalString(event.threadId);
    if (!threadId || !state.serverBaseUrl || !state.accessToken || !state.agentId) {
        throw new Error("DM delivery is missing required connection fields.");
    }
    const messagesResponse = await readDmThreadMessages(state.serverBaseUrl, state.accessToken, threadId);
    const messages = extractMessages(messagesResponse).slice(-24);
    const activityLevel = effectiveActivityLevel(safetyPolicy);
    if (shouldIgnoreForHumanConversationGate(event, activityLevel, "dm")) {
        return;
    }
    const replyText = await runEmbeddedReply(context, {
        account,
        kind: "dm",
        threadId,
        senderId: normalizeOptionalString(event.actorAgentId ?? event.actorUserId) ?? null,
        senderName: normalizeOptionalString(event.actorDisplayName) ?? null,
        senderUsername: normalizeOptionalString(event.actorHandle) ?? null,
        prompt: buildDmPrompt({
            selfAgentId: state.agentId,
            delivery,
            messages,
            activityLevel
        })
    });
    const target = deriveReplyTarget(event);
    await submitAndWaitForSuccess(state, {
        type: "dm.send",
        payload: {
            targetType: target.targetType,
            targetId: target.targetId,
            contentType: "text",
            content: replyText,
            metadata: {
                runtime: "openclaw-native-plugin",
                sourceDeliveryId: delivery.deliveryId,
                sessionKey: buildSessionKey(account, "dm", threadId)
            }
        }
    }, `agentschatapp-native-dm-${delivery.deliveryId}`);
}
async function processForumDelivery(context, account, state, delivery, safetyPolicy) {
    const event = asRecord(delivery.event);
    const threadId = normalizeOptionalString(event.threadId);
    if (!threadId || !state.serverBaseUrl || !state.accessToken || !state.agentId) {
        throw new Error("Forum delivery is missing required connection fields.");
    }
    const activityLevel = effectiveActivityLevel(safetyPolicy);
    if (!allowsSurfaceReplies(activityLevel, "forum")
        || isSelfAgentActor(event, state)
        || shouldIgnoreForHumanConversationGate(event, activityLevel, "forum")) {
        return;
    }
    const topicResponse = await readForumTopic(state.serverBaseUrl, state.accessToken, threadId);
    const topic = asRecord(topicResponse.topic);
    const replyText = await runEmbeddedReply(context, {
        account,
        kind: "forum",
        threadId,
        senderId: normalizeOptionalString(event.actorAgentId ?? event.actorUserId) ?? null,
        senderName: normalizeOptionalString(event.actorDisplayName) ?? null,
        prompt: buildForumPrompt({
            delivery,
            topic,
            activityLevel
        })
    });
    if (replyText.length === 0 || isNoReply(replyText)) {
        return;
    }
    const parentEventId = normalizeOptionalString(event.id);
    if (!parentEventId) {
        throw new Error("Forum delivery is missing event.id for parentEventId.");
    }
    await submitAndWaitForSuccess(state, {
        type: "forum.reply.create",
        payload: {
            threadId,
            parentEventId,
            contentType: "text",
            content: replyText,
            metadata: {
                runtime: "openclaw-native-plugin",
                sourceDeliveryId: delivery.deliveryId,
                sessionKey: buildSessionKey(account, "forum", threadId)
            }
        }
    }, `agentschatapp-native-forum-${delivery.deliveryId}`);
}
function isFormalDebater(debate, selfAgentId) {
    const seats = Array.isArray(debate.seats) ? debate.seats : [];
    return seats.some((seat) => {
        const seatAgentId = typeof seat.agentId === "string"
            ? seat.agentId
            : seat.agent != null && typeof seat.agent === "object" && typeof seat.agent.id === "string"
                ? seat.agent.id
                : undefined;
        return seatAgentId === selfAgentId;
    });
}
async function processDebateSpectatorDelivery(context, account, state, delivery, safetyPolicy) {
    const event = asRecord(delivery.event);
    const debateSessionId = normalizeOptionalString(event.targetId);
    if (!state.serverBaseUrl || !state.accessToken || !state.agentId || !debateSessionId) {
        throw new Error("Live delivery is missing required connection fields.");
    }
    const activityLevel = effectiveActivityLevel(safetyPolicy);
    if (!allowsSurfaceReplies(activityLevel, "live")
        || isSelfAgentActor(event, state)
        || shouldIgnoreForHumanConversationGate(event, activityLevel, "live")) {
        return;
    }
    const debate = unwrapDebate(await readDebate(state.serverBaseUrl, debateSessionId));
    if (isFormalDebater(debate, state.agentId)) {
        return;
    }
    const replyText = await runEmbeddedReply(context, {
        account,
        kind: "live",
        threadId: debateSessionId,
        senderId: normalizeOptionalString(event.actorAgentId ?? event.actorUserId) ?? null,
        senderName: normalizeOptionalString(event.actorDisplayName) ?? null,
        prompt: buildDebateSpectatorPrompt({
            delivery,
            debate,
            activityLevel
        })
    });
    if (replyText.length === 0 || isNoReply(replyText)) {
        return;
    }
    await submitAndWaitForSuccess(state, {
        type: "debate.spectator.post",
        payload: {
            debateSessionId,
            contentType: "text",
            content: replyText,
            metadata: {
                runtime: "openclaw-native-plugin",
                sourceDeliveryId: delivery.deliveryId,
                sessionKey: buildSessionKey(account, "live", debateSessionId)
            }
        }
    }, `agentschatapp-native-live-${delivery.deliveryId}`);
}
async function processDebateDelivery(context, account, state, delivery, safetyPolicy) {
    const event = asRecord(delivery.event);
    const metadata = asRecord(event.metadata);
    const debateSessionId = normalizeOptionalString(event.targetId);
    if (!state.serverBaseUrl || !state.accessToken || !state.agentId || !debateSessionId) {
        throw new Error("Debate delivery is missing required connection fields.");
    }
    if (metadata.agentId !== state.agentId) {
        return;
    }
    const debate = unwrapDebate(await readDebate(state.serverBaseUrl, debateSessionId));
    const activityLevel = effectiveActivityLevel(safetyPolicy);
    const turnText = await runEmbeddedReply(context, {
        account,
        kind: "debate",
        threadId: debateSessionId,
        senderId: normalizeOptionalString(metadata.agentId) ?? null,
        senderName: normalizeOptionalString(event.actorDisplayName) ?? null,
        prompt: buildDebatePrompt({
            delivery,
            debate,
            activityLevel
        })
    });
    if (turnText.length === 0 || isNoReply(turnText)) {
        return;
    }
    await submitAndWaitForSuccess(state, {
        type: "debate.turn.submit",
        payload: {
            debateSessionId,
            seatId: metadata.seatId,
            turnNumber: metadata.turnNumber,
            contentType: "text",
            content: turnText,
            metadata: {
                runtime: "openclaw-native-plugin",
                sourceDeliveryId: delivery.deliveryId,
                sessionKey: buildSessionKey(account, "debate", debateSessionId)
            }
        }
    }, `agentschatapp-native-debate-${delivery.deliveryId}`);
}
async function processDelivery(context, account, state, delivery, safetyPolicy, logger) {
    const event = asRecord(delivery.event);
    switch (event.type) {
        case "dm.received":
            await processDmDelivery(context, account, state, delivery, safetyPolicy);
            return true;
        case "forum.reply.create":
            await processForumDelivery(context, account, state, delivery, safetyPolicy);
            return true;
        case "debate.turn.assigned":
            await processDebateDelivery(context, account, state, delivery, safetyPolicy);
            return true;
        case "debate.spectator.post":
            await processDebateSpectatorDelivery(context, account, state, delivery, safetyPolicy);
            return true;
        case "claim.requested":
            logger.warn(`Agents Chat slot '${account.slot}' received claim.requested. Native plugin does not auto-confirm claims.`);
            return true;
        default:
            logger.warn(`Agents Chat slot '${account.slot}' received unsupported delivery type '${normalizeOptionalString(event.type) ?? "unknown"}', acknowledging without action.`);
            return true;
    }
}
async function handleDeliveryBatch(context, account, state, deliveries, logger) {
    if (deliveries.length === 0 || !state.serverBaseUrl || !state.accessToken) {
        return;
    }
    const safetyPolicy = await loadSafetyPolicy(state, logger);
    const ackIds = [];
    for (const delivery of deliveries) {
        const deliveryId = normalizeOptionalString(delivery.deliveryId);
        if (!deliveryId) {
            continue;
        }
        try {
            const shouldAck = await processDelivery(context, account, state, delivery, safetyPolicy, logger);
            if (shouldAck) {
                ackIds.push(deliveryId);
            }
        }
        catch (error) {
            logger.warn(`Agents Chat slot '${account.slot}' failed delivery ${deliveryId}, it will be retried: ${error instanceof Error ? error.message : String(error)}`);
        }
    }
    if (ackIds.length > 0) {
        await ackDeliveries(state.serverBaseUrl, state.accessToken, ackIds);
        state.lastInboundAt = nowIso();
    }
}
function computeRetryDelaySeconds(reconnectAttempts, error) {
    if (error instanceof AgentsChatConnectionStateError && error.code === "conflict") {
        return 60;
    }
    return DEFAULT_POLL_BACKOFF_SECONDS[Math.min(reconnectAttempts, DEFAULT_POLL_BACKOFF_SECONDS.length - 1)];
}
async function runWorkerLoop(context, account, controller, logger) {
    const runtimeState = ensureWorkerState(account.slot);
    runtimeState.running = true;
    runtimeState.connected = false;
    runtimeState.reconnectAttempts = 0;
    runtimeState.healthState = "idle";
    let reconnectAttempts = 0;
    while (!controller.signal.aborted) {
        let state = loadSlotState(account.slot, context.stateStore);
        state.mode = account.mode;
        state.agentSlotId = account.slot;
        try {
            if (!runtimeState.connected) {
                const shouldAllowLauncherReclaim = runtimeState.lastConnectedAt == null && reconnectAttempts === 0;
                state = await connectAccount(account, state, logger, {
                    allowLauncherReclaim: shouldAllowLauncherReclaim
                });
                state.lastError = null;
                state.degradedReason = null;
                state.conflictState = null;
                persistState(context, account.slot, state, runtimeState);
                runtimeState.connected = true;
                runtimeState.healthState = "healthy";
                runtimeState.degradedReason = null;
                runtimeState.conflictState = null;
                runtimeState.reconnectAttempts = reconnectAttempts;
                runtimeState.lastConnectedAt = parseIsoMs(state.lastConnectedAt) ?? nowMs();
            }
            if (!state.serverBaseUrl || !state.accessToken) {
                throw new Error("Connected slot still has no access token.");
            }
            const response = await pollDeliveries(state.serverBaseUrl, state.accessToken, DEFAULT_POLL_WAIT_SECONDS);
            const deliveries = extractDeliveries(response);
            await handleDeliveryBatch(context, account, state, deliveries, logger);
            let policy = await loadSafetyPolicy(state, logger);
            if (runtimeState.nextDiscoveryAt != null && nowMs() >= runtimeState.nextDiscoveryAt) {
                policy = await loadSafetyPolicy(state, logger, true);
            }
            await maybeRunHighActivityDiscovery({
                context,
                account,
                state,
                runtimeState,
                policy,
                submitAndWaitForSuccess,
                logger
            });
            persistState(context, account.slot, state, runtimeState);
            reconnectAttempts = 0;
            runtimeState.reconnectAttempts = 0;
            runtimeState.lastError = null;
            runtimeState.healthState = "healthy";
        }
        catch (error) {
            if (controller.signal.aborted) {
                break;
            }
            const message = error instanceof Error ? error.message : String(error);
            state.lastError = message;
            runtimeState.lastError = message;
            runtimeState.connected = false;
            runtimeState.reconnectAttempts = reconnectAttempts + 1;
            if (error instanceof AgentsChatConnectionStateError && error.code === "conflict") {
                state.conflictState = "connection_replaced";
                state.degradedReason = "conflict";
                runtimeState.conflictState = state.conflictState;
                runtimeState.degradedReason = state.degradedReason;
                runtimeState.healthState = "conflict";
            }
            else if (error instanceof AgentsChatHttpError && error.statusCode === 401 && state.agentId) {
                state.conflictState = "connection_replaced";
                state.degradedReason = "conflict";
                runtimeState.conflictState = state.conflictState;
                runtimeState.degradedReason = state.degradedReason;
                runtimeState.healthState = "conflict";
            }
            else {
                state.degradedReason =
                    error instanceof AgentsChatConnectionStateError ? error.code
                        : error instanceof AgentsChatNetworkError ? "network"
                            : "retrying";
                state.conflictState = null;
                runtimeState.degradedReason = state.degradedReason;
                runtimeState.conflictState = null;
                runtimeState.healthState = "degraded";
            }
            persistState(context, account.slot, state, runtimeState);
            const delaySeconds = computeRetryDelaySeconds(reconnectAttempts, error);
            reconnectAttempts += 1;
            logger.warn(`Agents Chat slot '${account.slot}' worker retrying in ${delaySeconds}s: ${message}`);
            try {
                await wait(delaySeconds * 1000, controller.signal);
            }
            catch {
                break;
            }
        }
    }
    const latestState = loadSlotState(account.slot, context.stateStore);
    runtimeState.running = false;
    runtimeState.connected = false;
    runtimeState.healthState = latestState.conflictState ? "conflict" : latestState.degradedReason ? "degraded" : "stopped";
    syncRuntimeFromState(runtimeState, latestState);
}
async function startAccountWorker(context, account, logger) {
    const existing = activeWorkers.get(account.slot);
    const nextFingerprint = accountFingerprint(account);
    if (existing && existing.fingerprint === nextFingerprint) {
        return;
    }
    if (existing) {
        await existing.stop("config changed");
    }
    const controller = new AbortController();
    const handle = {
        slot: account.slot,
        fingerprint: nextFingerprint,
        controller,
        stop: async () => {
            controller.abort();
            await handle.promise.catch(() => undefined);
            activeWorkers.delete(account.slot);
            const runtimeState = ensureWorkerState(account.slot);
            runtimeState.running = false;
            runtimeState.connected = false;
            if (runtimeState.healthState === "healthy") {
                runtimeState.healthState = "stopped";
            }
        },
        promise: Promise.resolve()
    };
    handle.promise = runWorkerLoop(context, account, controller, logger).finally(() => {
        activeWorkers.delete(account.slot);
        const runtimeState = ensureWorkerState(account.slot);
        runtimeState.running = false;
        runtimeState.connected = false;
        if (runtimeState.healthState === "healthy") {
            runtimeState.healthState = "stopped";
        }
    });
    activeWorkers.set(account.slot, handle);
}
async function runManagerReconcile(context, logger) {
    if (managerReconcilePromise) {
        return managerReconcilePromise;
    }
    managerReconcilePromise = (async () => {
        await reconcileManagedAccounts(context, logger);
    })().finally(() => {
        managerReconcilePromise = null;
    });
    return managerReconcilePromise;
}
export async function stopAccountWorker(slot) {
    const existing = activeWorkers.get(slot);
    if (!existing) {
        return;
    }
    await existing.stop("manual stop");
}
export async function reconcileManagedAccounts(context = managerContext, logger = managerLogger ?? context.logger) {
    const cfg = context.runtime.config.loadConfig();
    const desiredAccounts = listAgentsChatAccounts(cfg).filter((account) => account.autoStart !== false && isConfiguredAgentsChatAccount(account));
    const desiredSlots = new Set(desiredAccounts.map((account) => account.slot));
    for (const account of desiredAccounts) {
        await startAccountWorker(context, account, logger);
    }
    for (const [slot, handle] of activeWorkers) {
        if (!desiredSlots.has(slot)) {
            await handle.stop("account removed");
        }
    }
}
export async function startAgentsChatManager(context) {
    managerContext = context;
    managerLogger = context.logger;
    await runManagerReconcile(context, context.logger);
    if (managerTimer) {
        clearInterval(managerTimer);
    }
    managerTimer = setInterval(() => {
        void runManagerReconcile(context, context.logger).catch((error) => {
            context.logger.warn(`Agents Chat manager reconcile failed: ${error instanceof Error ? error.message : String(error)}`);
        });
    }, DEFAULT_MANAGER_INTERVAL_MS);
    managerTimer.unref?.();
}
export async function stopAgentsChatManager(_context) {
    if (managerTimer) {
        clearInterval(managerTimer);
        managerTimer = null;
    }
    const workers = [...activeWorkers.values()];
    for (const worker of workers) {
        await worker.stop("manager stop");
    }
    activeWorkers.clear();
    managerReconcilePromise = null;
    managerLogger = null;
    managerContext = null;
}
export function getWorkerSnapshot(slot) {
    return { ...ensureWorkerState(slot) };
}
export function clearWorkerConflict(slot) {
    const runtimeState = ensureWorkerState(slot);
    runtimeState.conflictState = null;
    runtimeState.degradedReason = null;
    if (runtimeState.healthState === "conflict") {
        runtimeState.healthState = runtimeState.running ? "healthy" : "idle";
    }
}
export function buildSnapshotForAccount(account) {
    const context = managerContext;
    const persisted = loadSlotState(account.slot, context?.stateStore);
    const runtimeState = ensureWorkerState(account.slot);
    return {
        accountId: account.slot,
        name: account.displayName ?? persisted.displayName ?? account.slot,
        enabled: account.autoStart !== false,
        configured: isConfiguredAgentsChatAccount(account, persisted),
        linked: Boolean(persisted.agentId),
        running: runtimeState.running,
        connected: runtimeState.connected,
        reconnectAttempts: runtimeState.reconnectAttempts,
        lastConnectedAt: runtimeState.lastConnectedAt ?? parseIsoMs(persisted.lastConnectedAt),
        lastInboundAt: runtimeState.lastInboundAt ?? parseIsoMs(persisted.lastInboundAt),
        lastOutboundAt: runtimeState.lastOutboundAt ?? parseIsoMs(persisted.lastOutboundAt),
        lastError: runtimeState.lastError ?? persisted.lastError ?? null,
        healthState: runtimeState.healthState,
        mode: account.mode,
        dmPolicy: persisted.safetyPolicy?.dmPolicyMode,
        baseUrl: persisted.serverBaseUrl ?? account.serverBaseUrl,
        profile: {
            agentId: persisted.agentId,
            handle: persisted.agentHandle,
            openclawAgent: account.openclawAgent,
            activityLevel: persisted.safetyPolicy?.activityLevel,
            allowProactiveInteractions: persisted.safetyPolicy?.allowProactiveInteractions
        }
    };
}
export async function disconnectAccount(slot, context) {
    await stopAccountWorker(slot);
    clearSlotState(slot, context.stateStore);
    clearWorkerConflict(slot);
}
