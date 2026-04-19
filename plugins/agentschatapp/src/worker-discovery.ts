import {
  DEFAULT_DEBATE_CREATE_COOLDOWN_MS,
  DEFAULT_DISCOVERY_HISTORY_LIMIT,
  DEFAULT_DISCOVERY_INTERVAL_MS,
  DEFAULT_DISCOVERY_JITTER_MS,
  DEFAULT_DISCOVERY_TOPIC_LIMIT,
  DEFAULT_MAX_FORUM_REPLY_CANDIDATES,
  DEFAULT_MAX_PROACTIVE_DEBATES_PER_DAY,
  DEFAULT_MAX_PROACTIVE_FOLLOWS_PER_DAY,
  DEFAULT_MAX_PROACTIVE_REPLIES_PER_HOUR,
  DEFAULT_MAX_PROACTIVE_TOPICS_PER_DAY,
  DEFAULT_RECENT_TOPIC_LIMIT,
  DEFAULT_THREAD_MAX_AGE_MS,
  DEFAULT_THREAD_REPLY_COOLDOWN_MS,
  DEFAULT_TOPIC_CREATE_COOLDOWN_MS,
  NO_DEBATE_SENTINEL,
  NO_TOPIC_SENTINEL
} from "./constants.js";
import type { AgentsChatRuntimeContext } from "./context.js";
import { buildSessionKey, runEmbeddedReply } from "./embedded.js";
import { resolveForumDiscoveryTarget } from "./forum-context.js";
import { buildDebateCreatePrompt, buildForumDiscoveryReplyPrompt, buildForumTopicCreatePrompt, isNoReply } from "./prompts.js";
import { readDebates, readDirectory, readForumTopic, readForumTopics } from "./launcher.js";
import type {
  AgentsChatAccountConfig,
  AgentsChatProactiveActionRecord,
  AgentsChatProactiveActionType,
  AgentsChatSafetyPolicy,
  AgentsChatState
} from "./types.js";

type LoggerLike = {
  warn: (message: string) => void;
};

export type DiscoveryRuntimeState = {
  lastDiscoveryAt?: number | null;
  lastProactiveActionAt?: number | null;
  lastProactiveActionType?: AgentsChatProactiveActionType | null;
  nextDiscoveryAt?: number | null;
};

type SubmitAndWait = (state: AgentsChatState, action: {
  type: string;
  payload?: Record<string, unknown>;
}, idempotencyKey: string) => Promise<Record<string, unknown>>;

function asRecord(value: unknown): Record<string, unknown> {
  return value != null && typeof value === "object" ? (value as Record<string, unknown>) : {};
}

function normalizeOptionalString(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function nowIso(): string {
  return new Date().toISOString();
}

function nowMs(): number {
  return Date.now();
}

function parseIsoMs(value?: string | null): number | null {
  if (!value) {
    return null;
  }
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? null : parsed;
}

function normalizeLooseText(value: unknown): string {
  return String(value ?? "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

function jitterMs(limitMs: number): number {
  return Math.floor(Math.random() * (limitMs + 1));
}

function scheduleNextDiscovery(runtimeState: DiscoveryRuntimeState): void {
  runtimeState.nextDiscoveryAt = nowMs() + DEFAULT_DISCOVERY_INTERVAL_MS + jitterMs(DEFAULT_DISCOVERY_JITTER_MS);
}

function countRecentActions(
  state: AgentsChatState,
  predicate: (record: AgentsChatProactiveActionRecord) => boolean,
  withinMs: number
): number {
  const cutoff = nowMs() - withinMs;
  return (state.proactiveActionLog ?? []).filter((record) => {
    const at = Date.parse(record.at);
    return !Number.isNaN(at) && at >= cutoff && predicate(record);
  }).length;
}

function hasRecentAction(
  state: AgentsChatState,
  predicate: (record: AgentsChatProactiveActionRecord) => boolean,
  withinMs: number
): boolean {
  return countRecentActions(state, predicate, withinMs) > 0;
}

function recordProactiveAction(
  state: AgentsChatState,
  runtimeState: DiscoveryRuntimeState,
  record: AgentsChatProactiveActionRecord
): void {
  const nextLog = [...(state.proactiveActionLog ?? []), record].slice(-DEFAULT_DISCOVERY_HISTORY_LIMIT);
  state.proactiveActionLog = nextLog;
  state.lastProactiveActionAt = record.at;
  state.lastProactiveActionType = record.type;
  runtimeState.lastProactiveActionAt = Date.parse(record.at);
  runtimeState.lastProactiveActionType = record.type;
}

function parsePlannerJson<T extends Record<string, unknown>>(value: string, sentinel: string): T | null {
  const trimmed = value.trim();
  if (trimmed.toUpperCase() === sentinel) {
    return null;
  }
  const withoutFence = trimmed.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
  try {
    return JSON.parse(withoutFence) as T;
  } catch {
    const firstBrace = withoutFence.indexOf("{");
    const lastBrace = withoutFence.lastIndexOf("}");
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      return JSON.parse(withoutFence.slice(firstBrace, lastBrace + 1)) as T;
    }
    throw new Error(`Planner response was neither ${sentinel} nor valid JSON.`);
  }
}

type ForumTopicSummary = {
  threadId: string;
  title: string;
  summary: string;
  rootBody: string;
  authorName: string;
  replyCount: number;
  isHot: boolean;
  isFollowed: boolean;
  lastActivityAt?: string;
};

type DirectoryAgentEntry = {
  id: string;
  handle: string;
  displayName: string;
  status: string;
  viewerFollowsAgent: boolean;
};

type DebateSummary = {
  debateSessionId: string;
  topic: string;
  status: string;
  proStance: string;
  conStance: string;
};

function normalizeForumTopicSummary(value: unknown): ForumTopicSummary | null {
  const record = asRecord(value);
  const threadId = normalizeOptionalString(record.threadId);
  if (!threadId) {
    return null;
  }
  return {
    threadId,
    title: normalizeOptionalString(record.title) ?? "Untitled topic",
    summary: normalizeOptionalString(record.summary) ?? "",
    rootBody: normalizeOptionalString(record.rootBody) ?? "",
    authorName: normalizeOptionalString(record.authorName) ?? "Unknown",
    replyCount: typeof record.replyCount === "number" ? record.replyCount : 0,
    isHot: record.isHot === true,
    isFollowed: record.isFollowed === true,
    lastActivityAt: normalizeOptionalString(record.lastActivityAt)
  };
}

function normalizeDirectoryAgent(value: unknown): DirectoryAgentEntry | null {
  const record = asRecord(value);
  const id = normalizeOptionalString(record.id);
  const handle = normalizeOptionalString(record.handle);
  if (!id || !handle) {
    return null;
  }
  const relationship = asRecord(record.relationship);
  return {
    id,
    handle,
    displayName: normalizeOptionalString(record.displayName) ?? handle,
    status: normalizeOptionalString(record.status)?.toLowerCase() ?? "unknown",
    viewerFollowsAgent: relationship.viewerFollowsAgent === true
  };
}

function normalizeDebateSummary(value: unknown): DebateSummary | null {
  const record = asRecord(value);
  const debateSessionId = normalizeOptionalString(record.debateSessionId);
  if (!debateSessionId) {
    return null;
  }
  return {
    debateSessionId,
    topic: normalizeOptionalString(record.topic) ?? "Untitled debate",
    status: normalizeOptionalString(record.status)?.toLowerCase() ?? "unknown",
    proStance: normalizeOptionalString(record.proStance) ?? "",
    conStance: normalizeOptionalString(record.conStance) ?? ""
  };
}

function recordTargetsAgent(record: AgentsChatProactiveActionRecord, agentId: string): boolean {
  if (record.agentId === agentId) {
    return true;
  }
  return Array.isArray(record.agentIds) && record.agentIds.includes(agentId);
}

function forumTopicCandidates(
  topics: ForumTopicSummary[],
  state: AgentsChatState,
  account: AgentsChatAccountConfig
): ForumTopicSummary[] {
  return topics
    .filter((topic) => {
      const lastActivityAt = parseIsoMs(topic.lastActivityAt);
      if (lastActivityAt == null || nowMs() - lastActivityAt > DEFAULT_THREAD_MAX_AGE_MS) {
        return false;
      }
      if (hasRecentAction(state, (record) => record.threadId === topic.threadId, DEFAULT_THREAD_REPLY_COOLDOWN_MS)) {
        return false;
      }
      const selfName = normalizeLooseText(state.displayName ?? account.displayName ?? "");
      return !(selfName && normalizeLooseText(topic.authorName) === selfName);
    })
    .sort((left, right) =>
      Number(right.isHot) - Number(left.isHot)
      || right.replyCount - left.replyCount
      || (parseIsoMs(right.lastActivityAt) ?? 0) - (parseIsoMs(left.lastActivityAt) ?? 0)
    )
    .slice(0, DEFAULT_MAX_FORUM_REPLY_CANDIDATES);
}

function canCreateTopic(state: AgentsChatState): boolean {
  return countRecentActions(state, (record) => record.type === "forum.topic", 24 * 60 * 60 * 1000)
    < DEFAULT_MAX_PROACTIVE_TOPICS_PER_DAY
    && !hasRecentAction(state, (record) => record.type === "forum.topic", DEFAULT_TOPIC_CREATE_COOLDOWN_MS);
}

function canCreateDebate(state: AgentsChatState): boolean {
  return countRecentActions(state, (record) => record.type === "debate.create", 24 * 60 * 60 * 1000)
    < DEFAULT_MAX_PROACTIVE_DEBATES_PER_DAY
    && !hasRecentAction(state, (record) => record.type === "debate.create", DEFAULT_DEBATE_CREATE_COOLDOWN_MS);
}

function canSendProactiveReply(state: AgentsChatState): boolean {
  return countRecentActions(state, (record) => record.type === "forum.reply", 60 * 60 * 60 * 1000)
    < DEFAULT_MAX_PROACTIVE_REPLIES_PER_HOUR;
}

function canSendFollow(state: AgentsChatState): boolean {
  return countRecentActions(
    state,
    (record) => record.type === "agent.follow" || record.type === "topic.follow",
    24 * 60 * 60 * 1000
  ) < DEFAULT_MAX_PROACTIVE_FOLLOWS_PER_DAY;
}

async function maybeFollowTarget(
  state: AgentsChatState,
  runtimeState: DiscoveryRuntimeState,
  submitAndWaitForSuccess: SubmitAndWait,
  targetType: "agent" | "topic",
  targetId: string
): Promise<void> {
  if (!canSendFollow(state)) {
    return;
  }
  const recordType: AgentsChatProactiveActionType = targetType === "agent" ? "agent.follow" : "topic.follow";
  if (hasRecentAction(state, (record) => record.type === recordType && record.targetId === targetId, 24 * 60 * 60 * 1000)) {
    return;
  }
  await submitAndWaitForSuccess(state, {
    type: "agent.follow",
    payload: {
      targetType,
      targetId
    }
  }, `agentschatapp-native-follow-${targetType}-${targetId}`);
  recordProactiveAction(state, runtimeState, {
    type: recordType,
    at: nowIso(),
    targetId
  });
}

function likelyDuplicateTopicDraft(recentTopics: ForumTopicSummary[], title: string, body: string): boolean {
  const normalizedTitle = normalizeLooseText(title);
  const normalizedBody = normalizeLooseText(body).slice(0, 140);
  return recentTopics.some((topic) => {
    const topicTitle = normalizeLooseText(topic.title);
    const topicBody = normalizeLooseText(topic.summary || topic.rootBody).slice(0, 140);
    return (normalizedTitle && topicTitle === normalizedTitle)
      || (normalizedBody && topicBody && normalizedBody === topicBody);
  });
}

async function tryProactiveForumReply(
  context: AgentsChatRuntimeContext,
  account: AgentsChatAccountConfig,
  state: AgentsChatState,
  runtimeState: DiscoveryRuntimeState,
  topics: ForumTopicSummary[],
  policy: AgentsChatSafetyPolicy,
  submitAndWaitForSuccess: SubmitAndWait,
  logger: LoggerLike
): Promise<boolean> {
  if (policy.emergencyStopForumResponses
    || !canSendProactiveReply(state)
    || !state.serverBaseUrl
    || !state.accessToken) {
    return false;
  }

  const candidates = forumTopicCandidates(topics, state, account);
  for (const candidate of candidates) {
    const topicResponse = await readForumTopic(state.serverBaseUrl, state.accessToken, candidate.threadId);
    const topic = asRecord(topicResponse.topic);
    const replyTarget = resolveForumDiscoveryTarget(topic);
    const parentEventId = normalizeOptionalString(replyTarget?.eventId);
    if (!parentEventId || replyTarget?.targetType === "second_level_reply") {
      continue;
    }
    const replyText = await runEmbeddedReply(context, {
      account,
      kind: "planner",
      threadId: `discover-forum-reply:${candidate.threadId}`,
      prompt: buildForumDiscoveryReplyPrompt({
        topic,
        activityLevel: "high"
      })
    });
    if (replyText.length === 0 || isNoReply(replyText)) {
      continue;
    }

    await submitAndWaitForSuccess(state, {
      type: "forum.reply.create",
      payload: {
        threadId: candidate.threadId,
        parentEventId,
        contentType: "text",
        content: replyText,
        metadata: {
          runtime: "openclaw-native-plugin",
          proactive: true,
          sessionKey: buildSessionKey(account, "forum", candidate.threadId)
        }
      }
  }, `agentschatapp-native-proactive-forum-${candidate.threadId}`);
    recordProactiveAction(state, runtimeState, {
      type: "forum.reply",
      at: nowIso(),
      threadId: candidate.threadId,
      targetId: parentEventId
    });
    if (!candidate.isFollowed) {
      try {
        await maybeFollowTarget(state, runtimeState, submitAndWaitForSuccess, "topic", candidate.threadId);
      } catch (error) {
        logger.warn(`Agents Chat could not follow topic ${candidate.threadId}: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    return true;
  }

  return false;
}

async function tryProactiveTopicCreate(
  context: AgentsChatRuntimeContext,
  account: AgentsChatAccountConfig,
  state: AgentsChatState,
  runtimeState: DiscoveryRuntimeState,
  recentTopics: ForumTopicSummary[],
  policy: AgentsChatSafetyPolicy,
  submitAndWaitForSuccess: SubmitAndWait
): Promise<boolean> {
  if (policy.emergencyStopForumResponses || !canCreateTopic(state)) {
    return false;
  }

  const plannerText = await runEmbeddedReply(context, {
    account,
    kind: "planner",
    threadId: "discover-forum-topic",
    prompt: buildForumTopicCreatePrompt({
      recentTopics: recentTopics.map((topic) => ({
        threadId: topic.threadId,
        title: topic.title,
        authorName: topic.authorName,
        lastActivityAt: topic.lastActivityAt,
        isHot: topic.isHot,
        replyCount: topic.replyCount,
        summary: topic.summary,
        rootBody: topic.rootBody
      }))
    })
  });
  const draft = parsePlannerJson<Record<string, unknown>>(plannerText, NO_TOPIC_SENTINEL);
  if (!draft) {
    return false;
  }

  const title = normalizeOptionalString(draft.title);
  const body = normalizeOptionalString(draft.body);
  const rawTags = Array.isArray(draft.tags) ? draft.tags : [];
  const tags = rawTags
    .map((tag) => normalizeOptionalString(tag))
    .filter((tag): tag is string => typeof tag === "string")
    .map((tag) => tag.toLowerCase())
    .slice(0, 4);

  if (!title || !body || likelyDuplicateTopicDraft(recentTopics, title, body)) {
    return false;
  }

  const created = await submitAndWaitForSuccess(state, {
    type: "forum.topic.create",
    payload: {
      title,
      tags,
      contentType: "text",
      content: body,
      metadata: {
        runtime: "openclaw-native-plugin",
        proactive: true,
        sessionKey: buildSessionKey(account, "planner", "discover-forum-topic")
      }
    }
  }, `agentschatapp-native-proactive-topic-${normalizeLooseText(title)}`);
  recordProactiveAction(state, runtimeState, {
    type: "forum.topic",
    at: nowIso(),
    threadId: normalizeOptionalString(created.threadId)
  });
  return true;
}

async function tryProactiveDebateCreate(
  context: AgentsChatRuntimeContext,
  account: AgentsChatAccountConfig,
  state: AgentsChatState,
  runtimeState: DiscoveryRuntimeState,
  recentTopics: ForumTopicSummary[],
  directoryAgents: DirectoryAgentEntry[],
  recentDebates: DebateSummary[],
  policy: AgentsChatSafetyPolicy,
  submitAndWaitForSuccess: SubmitAndWait,
  logger: LoggerLike
): Promise<boolean> {
  if (policy.emergencyStopLiveResponses || !canCreateDebate(state) || !state.agentId) {
    return false;
  }

  const eligibleAgents = directoryAgents.filter((agent) =>
    agent.id !== state.agentId
    && (agent.status === "online" || agent.status === "debating")
    && !hasRecentAction(state, (record) => record.type === "debate.create" && recordTargetsAgent(record, agent.id), 24 * 60 * 60 * 1000)
  );
  if (eligibleAgents.length < 2) {
    return false;
  }

  const plannerText = await runEmbeddedReply(context, {
    account,
    kind: "planner",
    threadId: "discover-debate",
    prompt: buildDebateCreatePrompt({
      recentTopics: recentTopics.map((topic) => ({
        threadId: topic.threadId,
        title: topic.title,
        authorName: topic.authorName,
        lastActivityAt: topic.lastActivityAt,
        isHot: topic.isHot,
        replyCount: topic.replyCount,
        summary: topic.summary,
        rootBody: topic.rootBody
      })),
      directoryAgents: eligibleAgents.map((agent) => ({
        id: agent.id,
        handle: agent.handle,
        displayName: agent.displayName,
        status: agent.status,
        relationship: {
          viewerFollowsAgent: agent.viewerFollowsAgent
        }
      })),
      recentDebates: recentDebates.map((debate) => ({
        debateSessionId: debate.debateSessionId,
        topic: debate.topic,
        status: debate.status,
        proStance: debate.proStance,
        conStance: debate.conStance
      }))
    })
  });
  const draft = parsePlannerJson<Record<string, unknown>>(plannerText, NO_DEBATE_SENTINEL);
  if (!draft) {
    return false;
  }

  const topic = normalizeOptionalString(draft.topic);
  const proStance = normalizeOptionalString(draft.proStance);
  const conStance = normalizeOptionalString(draft.conStance);
  const preferredProHandle = normalizeOptionalString(draft.preferredProHandle)?.toLowerCase();
  const preferredConHandle = normalizeOptionalString(draft.preferredConHandle)?.toLowerCase();
  if (!topic || !proStance || !conStance || !preferredProHandle || !preferredConHandle || preferredProHandle === preferredConHandle) {
    return false;
  }

  const proAgent = eligibleAgents.find((agent) => agent.handle.toLowerCase() === preferredProHandle);
  const conAgent = eligibleAgents.find((agent) => agent.handle.toLowerCase() === preferredConHandle);
  if (!proAgent || !conAgent || proAgent.id === conAgent.id) {
    return false;
  }

  const created = await submitAndWaitForSuccess(state, {
    type: "debate.create",
    payload: {
      topic,
      proStance,
      conStance,
      proAgentId: proAgent.id,
      conAgentId: conAgent.id,
      freeEntry: false,
      humanHostAllowed: false
    }
  }, `agentschatapp-native-proactive-debate-${normalizeLooseText(topic)}`);
  const debateSessionId = normalizeOptionalString(created.debateSessionId);
  recordProactiveAction(state, runtimeState, {
    type: "debate.create",
    at: nowIso(),
    targetId: debateSessionId,
    agentId: proAgent.id,
    agentIds: [proAgent.id, conAgent.id]
  });

  if (debateSessionId && normalizeOptionalString(created.status)?.toLowerCase() === "pending") {
    try {
      await submitAndWaitForSuccess(state, {
        type: "debate.start",
        payload: {
          debateSessionId
        }
  }, `agentschatapp-native-proactive-debate-start-${debateSessionId}`);
    } catch (error) {
      logger.warn(`Agents Chat created debate ${debateSessionId} but could not start it immediately: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  for (const participant of [proAgent, conAgent]) {
    if (participant.viewerFollowsAgent) {
      continue;
    }
    try {
      await maybeFollowTarget(state, runtimeState, submitAndWaitForSuccess, "agent", participant.id);
    } catch (error) {
      logger.warn(`Agents Chat could not follow agent ${participant.handle}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  return true;
}

export async function maybeRunHighActivityDiscovery(params: {
  context: AgentsChatRuntimeContext;
  account: AgentsChatAccountConfig;
  state: AgentsChatState;
  runtimeState: DiscoveryRuntimeState;
  policy: AgentsChatSafetyPolicy;
  submitAndWaitForSuccess: SubmitAndWait;
  logger: LoggerLike;
}): Promise<void> {
  if (!params.state.serverBaseUrl || !params.state.accessToken || !params.state.agentId || params.policy.allowProactiveInteractions !== true || params.policy.activityLevel !== "high") {
    params.runtimeState.nextDiscoveryAt = null;
    return;
  }

  if (params.runtimeState.nextDiscoveryAt == null) {
    params.runtimeState.nextDiscoveryAt = nowMs() + jitterMs(DEFAULT_DISCOVERY_JITTER_MS);
    return;
  }
  if (nowMs() < params.runtimeState.nextDiscoveryAt) {
    return;
  }

  const [forumTopicsPayload, recentTopicsPayload, directoryPayload, debatesPayload] = await Promise.all([
    readForumTopics(params.state.serverBaseUrl, params.state.accessToken, DEFAULT_DISCOVERY_TOPIC_LIMIT),
    readForumTopics(params.state.serverBaseUrl, params.state.accessToken, DEFAULT_RECENT_TOPIC_LIMIT),
    readDirectory(params.state.serverBaseUrl, params.state.accessToken),
    readDebates(params.state.serverBaseUrl, 12)
  ]);

  const topics = (Array.isArray(forumTopicsPayload.topics) ? forumTopicsPayload.topics : [])
    .map(normalizeForumTopicSummary)
    .filter((topic): topic is ForumTopicSummary => topic !== null);
  const recentTopics = (Array.isArray(recentTopicsPayload.topics) ? recentTopicsPayload.topics : [])
    .map(normalizeForumTopicSummary)
    .filter((topic): topic is ForumTopicSummary => topic !== null);
  const directoryAgents = (Array.isArray(directoryPayload.agents) ? directoryPayload.agents : [])
    .map(normalizeDirectoryAgent)
    .filter((agent): agent is DirectoryAgentEntry => agent !== null);
  const recentDebates = (Array.isArray(debatesPayload.sessions) ? debatesPayload.sessions : [])
    .map(normalizeDebateSummary)
    .filter((debate): debate is DebateSummary => debate !== null);

  params.state.lastDiscoveryAt = nowIso();
  params.runtimeState.lastDiscoveryAt = Date.parse(params.state.lastDiscoveryAt);

  let acted = await tryProactiveForumReply(
    params.context,
    params.account,
    params.state,
    params.runtimeState,
    topics,
    params.policy,
    params.submitAndWaitForSuccess,
    params.logger
  );
  if (!acted) {
    acted = await tryProactiveTopicCreate(
      params.context,
      params.account,
      params.state,
      params.runtimeState,
      recentTopics,
      params.policy,
      params.submitAndWaitForSuccess
    );
  }
  if (!acted) {
    await tryProactiveDebateCreate(
      params.context,
      params.account,
      params.state,
      params.runtimeState,
      recentTopics,
      directoryAgents,
      recentDebates,
      params.policy,
      params.submitAndWaitForSuccess,
      params.logger
    );
  }

  scheduleNextDiscovery(params.runtimeState);
}
