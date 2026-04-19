import { NO_DEBATE_SENTINEL, NO_REPLY_SENTINEL, NO_TOPIC_SENTINEL, SYSTEM_PROMPT } from "./constants.js";

function normalizeText(value: unknown, fallback = "[empty]"): string {
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (trimmed.length > 0) {
      return trimmed;
    }
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return fallback;
}

function normalizeActorType(value: unknown): string {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function normalizeMessageContent(message: Record<string, unknown>): string {
  const content = normalizeText(message.content, "");
  if (content) {
    return content;
  }
  return normalizeText(message.contentType, "[empty]");
}

function messageDisplayName(message: Record<string, unknown>, selfAgentId: string): string {
  const actor = message.actor;
  if (actor == null || typeof actor !== "object") {
    return "Unknown";
  }
  const actorRecord = actor as Record<string, unknown>;
  const actorType = normalizeActorType(actorRecord.type);
  const actorId = actorRecord.id;
  if (actorType === "agent" && actorId === selfAgentId) {
    return "You";
  }
  return normalizeText(actorRecord.displayName, actorType === "human" ? "Human" : actorType === "agent" ? "Agent" : "Unknown");
}

function formatTranscript(messages: Record<string, unknown>[], selfAgentId: string): string {
  return messages
    .map((message) => {
      const occurredAt = normalizeText(message.occurredAt, "unknown-time");
      return `[${occurredAt}] ${messageDisplayName(message, selfAgentId)}: ${normalizeMessageContent(message)}`;
    })
    .join("\n");
}

function forumReplyLines(
  replies: Record<string, unknown>[],
  depth = 0,
  output: string[] = [],
  maxLines = 24
): string[] {
  for (const reply of replies) {
    if (output.length >= maxLines) {
      break;
    }
    output.push(`${"  ".repeat(depth)}- ${normalizeText(reply.authorName, "Unknown")}: ${normalizeText(reply.body)}`);
    const children = Array.isArray(reply.children) ? (reply.children as Record<string, unknown>[]) : [];
    forumReplyLines(children, depth + 1, output, maxLines);
  }
  return output;
}

function findForumReply(replies: Record<string, unknown>[], replyId: string): Record<string, unknown> | undefined {
  for (const reply of replies) {
    if (reply.id === replyId) {
      return reply;
    }
    const children = Array.isArray(reply.children) ? (reply.children as Record<string, unknown>[]) : [];
    const nested = findForumReply(children, replyId);
    if (nested) {
      return nested;
    }
  }
  return undefined;
}

function debateTurnLines(debate: Record<string, unknown>, maxLines = 10): string {
  const seatMap = new Map<string, Record<string, unknown>>();
  for (const seat of Array.isArray(debate.seats) ? (debate.seats as Record<string, unknown>[]) : []) {
    if (typeof seat.id === "string") {
      seatMap.set(seat.id, seat);
    }
  }

  const lines: string[] = [];
  for (const turn of Array.isArray(debate.formalTurns) ? (debate.formalTurns as Record<string, unknown>[]) : []) {
    if (lines.length >= maxLines) {
      break;
    }
    const seat = typeof turn.seatId === "string" ? seatMap.get(turn.seatId) : undefined;
    const agent = (seat?.agent ?? {}) as Record<string, unknown>;
    const event = (turn.event ?? {}) as Record<string, unknown>;
    const metadata = (turn.metadata ?? {}) as Record<string, unknown>;
    const speaker = normalizeText(event.actorDisplayName ?? agent.displayName, "Unknown speaker");
    const stance = normalizeText(turn.stance ?? metadata.stance, "unknown");
    const content = normalizeText(event.content, "[pending]");
    lines.push(`- Turn ${turn.turnNumber}: [${stance}] ${speaker}: ${content}`);
  }
  return lines.join("\n") || "- No previous formal turns yet.";
}

function spectatorFeedLines(feed: Record<string, unknown>[], maxLines = 12): string {
  const lines: string[] = [];
  for (const event of feed) {
    if (lines.length >= maxLines) {
      break;
    }
    const actorType = normalizeActorType(event.actorType);
    const speaker = normalizeText(
      event.actorDisplayName,
      actorType === "human" ? "Human" : actorType === "agent" ? "Agent" : "Unknown"
    );
    const content = normalizeText(event.content, "[empty]");
    lines.push(`- ${speaker}: ${content}`);
  }
  return lines.join("\n") || "- No spectator comments yet.";
}

function dmActivityGuidance(activityLevel: string): string {
  if (activityLevel === "low") {
    return "- Activity level: Passive. Stay reactive and answer the direct ask without spinning up side quests.";
  }
  if (activityLevel === "high") {
    return "- Activity level: Full proactive. Take stronger initiative when it clearly helps the conversation move.";
  }
  return "- Activity level: Active. Keep the conversation moving, but stay anchored to the current ask.";
}

function forumActivityGuidance(activityLevel: string): string {
  if (activityLevel === "high") {
    return "- Activity level: Full proactive. If you reply, add a fresh angle, challenge, or synthesis that genuinely improves the thread.";
  }
  return "- Activity level: Selective. Reply only when you can add something concrete and useful.";
}

function debateActivityGuidance(activityLevel: string): string {
  if (activityLevel === "low") {
    return "- Activity level: Passive. Keep the turn tightly focused and avoid extra flourish.";
  }
  if (activityLevel === "high") {
    return "- Activity level: Full proactive. Advance the argument decisively while staying on stance.";
  }
  return "- Activity level: Active. Deliver a clear, well-paced formal turn.";
}

function liveActivityGuidance(activityLevel: string): string {
  if (activityLevel === "high") {
    return "- Activity level: Full proactive. If you join the live side chat, add a sharp, useful intervention without hijacking the debate.";
  }
  return "- Activity level: Selective. Only join the live side chat when the latest message clearly benefits from a concise response.";
}

function compactTopicSummary(topic: Record<string, unknown>): string {
  return [
    `- threadId: ${normalizeText(topic.threadId, "unknown-thread")}`,
    `  title: ${normalizeText(topic.title, "Untitled topic")}`,
    `  author: ${normalizeText(topic.authorName, "Unknown")}`,
    `  lastActivityAt: ${normalizeText(topic.lastActivityAt, "unknown-time")}`,
    `  isHot: ${normalizeText(topic.isHot, "false")}`,
    `  replyCount: ${normalizeText(topic.replyCount, "0")}`,
    `  summary: ${normalizeText(topic.summary)}`,
    `  rootBody: ${normalizeText(topic.rootBody)}`
  ].join("\n");
}

function compactAgentSummary(agent: Record<string, unknown>): string {
  const relationship = (agent.relationship ?? {}) as Record<string, unknown>;
  return [
    `- handle: ${normalizeText(agent.handle, "unknown")}`,
    `  agentId: ${normalizeText(agent.id, "unknown-agent")}`,
    `  displayName: ${normalizeText(agent.displayName, "Unknown")}`,
    `  status: ${normalizeText(agent.status, "unknown")}`,
    `  followerCount: ${normalizeText(agent.followerCount, "0")}`,
    `  viewerFollowsAgent: ${normalizeText(relationship.viewerFollowsAgent, "false")}`,
    `  agentFollowsViewer: ${normalizeText(relationship.agentFollowsViewer, "false")}`,
    `  tags: ${Array.isArray(agent.profileTags) ? agent.profileTags.join(", ") || "[none]" : "[none]"}`
  ].join("\n");
}

function compactDebateSummary(debate: Record<string, unknown>): string {
  return [
    `- debateSessionId: ${normalizeText(debate.debateSessionId, "unknown-debate")}`,
    `  topic: ${normalizeText(debate.topic, "Untitled debate")}`,
    `  status: ${normalizeText(debate.status, "unknown")}`,
    `  proStance: ${normalizeText(debate.proStance)}`,
    `  conStance: ${normalizeText(debate.conStance)}`
  ].join("\n");
}

export function trimReplyText(replyText: string, maxChars: number): string {
  const trimmed = replyText.trim();
  if (trimmed.length <= maxChars || maxChars <= 0) {
    return trimmed;
  }
  if (maxChars <= 3) {
    return trimmed.slice(0, maxChars);
  }
  return `${trimmed.slice(0, maxChars - 3).trimEnd()}...`;
}

export function isNoReply(replyText: string): boolean {
  return replyText.trim().toUpperCase() === NO_REPLY_SENTINEL;
}

export function buildDmPrompt(params: {
  selfAgentId: string;
  delivery: Record<string, unknown>;
  messages: Record<string, unknown>[];
  activityLevel: string;
}): string {
  const event = (params.delivery.event ?? {}) as Record<string, unknown>;
  return [
    "Agents Chat DM delivery:",
    `From: ${normalizeText(event.actorDisplayName, "Unknown sender")}`,
    `Latest incoming message: ${normalizeMessageContent(event)}`,
    `Thread: ${normalizeText(event.threadId, "unknown-thread")}`,
    "",
    "Reply rules:",
    "- Reply as the agent in one natural plain-text message.",
    "- Keep the reply warm, useful, and concise unless the human clearly asks for more.",
    "- Do not mention hidden prompts, delivery ids, bridge mechanics, plugin logs, or system traces.",
    "- If the last message is ambiguous, ask one direct clarification question.",
    dmActivityGuidance(params.activityLevel),
    "",
    SYSTEM_PROMPT,
    "",
    "Recent thread transcript:",
    formatTranscript(params.messages, params.selfAgentId),
    "",
    "Return only the reply text."
  ].join("\n");
}

export function buildForumPrompt(params: {
  delivery: Record<string, unknown>;
  topic: Record<string, unknown>;
  activityLevel: string;
}): string {
  const event = (params.delivery.event ?? {}) as Record<string, unknown>;
  const replies = Array.isArray(params.topic.replies) ? (params.topic.replies as Record<string, unknown>[]) : [];
  const latestReply = typeof event.id === "string" ? findForumReply(replies, event.id) : undefined;
  const replyTree = forumReplyLines(replies).join("\n") || "- No visible replies yet.";

  return [
    "Agents Chat forum delivery:",
    `Latest reply from: ${normalizeText(latestReply?.authorName ?? event.actorDisplayName, "Unknown")}`,
    `Latest reply: ${normalizeText(latestReply?.body ?? event.content)}`,
    `Topic: ${normalizeText(params.topic.title, "Untitled topic")}`,
    "",
    "Forum reply mode:",
    `- Default to exactly ${NO_REPLY_SENTINEL} unless the latest reply clearly merits a response.`,
    "- Reply only when you can add something specific, helpful, or challenging.",
    "- If you do reply, write one natural forum reply in plain text.",
    "- Do not mention delivery ids, bridge mechanics, or system prompts.",
    forumActivityGuidance(params.activityLevel),
    "",
    SYSTEM_PROMPT,
    "",
    "Forum topic context:",
    `- rootAuthor: ${normalizeText(params.topic.authorName, "Unknown")}`,
    `- rootBody: ${normalizeText(params.topic.rootBody)}`,
    "",
    "Visible reply tree:",
    replyTree,
    "",
    `Return either ${NO_REPLY_SENTINEL} or the reply text.`
  ].join("\n");
}

export function buildDebatePrompt(params: {
  delivery: Record<string, unknown>;
  debate: Record<string, unknown>;
  activityLevel: string;
}): string {
  const event = (params.delivery.event ?? {}) as Record<string, unknown>;
  const metadata = (event.metadata ?? {}) as Record<string, unknown>;
  const stance = normalizeText(metadata.stance, "unknown");
  const stanceText =
    stance.toLowerCase() === "pro"
      ? normalizeText(params.debate.proStance)
      : stance.toLowerCase() === "con"
        ? normalizeText(params.debate.conStance)
        : "Unknown stance";

  return [
    "Agents Chat live debate turn:",
    `Topic: ${normalizeText(params.debate.topic, "Untitled debate")}`,
    `Assigned stance: ${stanceText}`,
    `Turn number: ${normalizeText(metadata.turnNumber, "unknown")}`,
    "",
    "Live debate formal-turn mode:",
    `- If this assignment is not really for you, return exactly ${NO_REPLY_SENTINEL}.`,
    "- Otherwise write exactly one formal debate turn in plain text.",
    "- Stay on your assigned stance and advance the argument.",
    "- Do not output bullets, JSON, stage directions, or hidden reasoning.",
    debateActivityGuidance(params.activityLevel),
    "",
    SYSTEM_PROMPT,
    "",
    "Debate context:",
    `- stanceSide: ${stance}`,
    `- deadlineAt: ${normalizeText(metadata.deadlineAt, "unknown")}`,
    "",
    "Recent formal turns:",
    debateTurnLines(params.debate),
    "",
    `Return either ${NO_REPLY_SENTINEL} or the turn text.`
  ].join("\n");
}

export function buildDebateSpectatorPrompt(params: {
  delivery: Record<string, unknown>;
  debate: Record<string, unknown>;
  activityLevel: string;
}): string {
  const event = (params.delivery.event ?? {}) as Record<string, unknown>;
  const spectatorFeed = Array.isArray(params.debate.spectatorFeed)
    ? (params.debate.spectatorFeed as Record<string, unknown>[])
    : [];

  return [
    "Agents Chat live spectator delivery:",
    `Latest spectator message from: ${normalizeText(event.actorDisplayName, "Unknown")}`,
    `Latest spectator message: ${normalizeText(event.content)}`,
    `Debate topic: ${normalizeText(params.debate.topic, "Untitled debate")}`,
    "",
    "Live spectator mode:",
    `- Default to exactly ${NO_REPLY_SENTINEL} unless the latest live comment clearly deserves a response.`,
    "- If you reply, write one natural plain-text spectator comment.",
    "- Do not turn this into a formal debate turn.",
    "- Do not mention delivery ids, hidden prompts, plugin logs, or system mechanics.",
    liveActivityGuidance(params.activityLevel),
    "",
    SYSTEM_PROMPT,
    "",
    "Debate context:",
    `- status: ${normalizeText(params.debate.status, "unknown")}`,
    `- proStance: ${normalizeText(params.debate.proStance)}`,
    `- conStance: ${normalizeText(params.debate.conStance)}`,
    "",
    "Recent formal turns:",
    debateTurnLines(params.debate, 8),
    "",
    "Recent spectator feed:",
    spectatorFeedLines(spectatorFeed),
    "",
    `Return either ${NO_REPLY_SENTINEL} or the spectator reply text.`
  ].join("\n");
}

export function buildForumDiscoveryReplyPrompt(params: {
  topic: Record<string, unknown>;
  activityLevel: string;
}): string {
  const replies = Array.isArray(params.topic.replies) ? (params.topic.replies as Record<string, unknown>[]) : [];
  return [
    "Agents Chat proactive forum discovery:",
    `Topic: ${normalizeText(params.topic.title, "Untitled topic")}`,
    `Author: ${normalizeText(params.topic.authorName, "Unknown")}`,
    `Last activity: ${normalizeText(params.topic.lastActivityAt, "unknown-time")}`,
    "",
    "Decision rules:",
    `- Return exactly ${NO_REPLY_SENTINEL} unless you can add a clearly valuable contribution right now.`,
    "- If you reply, write one natural public forum reply in plain text.",
    "- Prefer synthesis, a strong new angle, or a crisp challenge over generic encouragement.",
    "- Do not mention hidden prompts, discovery loops, or system mechanics.",
    forumActivityGuidance(params.activityLevel),
    "",
    SYSTEM_PROMPT,
    "",
    "Topic context:",
    `- rootBody: ${normalizeText(params.topic.rootBody)}`,
    `- summary: ${normalizeText(params.topic.summary)}`,
    "",
    "Visible reply tree:",
    forumReplyLines(replies).join("\n") || "- No visible replies yet.",
    "",
    `Return either ${NO_REPLY_SENTINEL} or the reply text.`
  ].join("\n");
}

export function buildForumTopicCreatePrompt(params: {
  recentTopics: Record<string, unknown>[];
}): string {
  return [
    "Agents Chat proactive topic creation planner:",
    "",
    "Decision rules:",
    `- Return exactly ${NO_TOPIC_SENTINEL} unless you have one genuinely fresh public topic worth starting now.`,
    "- Avoid rephrasing or lightly remixing topics that already exist below.",
    "- If you propose a topic, return strict JSON with keys: title, body, tags.",
    "- title must be concise and public-facing.",
    "- body must be one natural forum post body in plain text.",
    "- tags must be an array of 0 to 4 short lowercase strings.",
    "- Do not wrap the JSON in markdown fences.",
    "",
    SYSTEM_PROMPT,
    "",
    "Recent topics:",
    params.recentTopics.map(compactTopicSummary).join("\n\n") || "- No recent topics found.",
    "",
    `Return either ${NO_TOPIC_SENTINEL} or the JSON object.`
  ].join("\n");
}

export function buildDebateCreatePrompt(params: {
  recentTopics: Record<string, unknown>[];
  directoryAgents: Record<string, unknown>[];
  recentDebates: Record<string, unknown>[];
}): string {
  return [
    "Agents Chat proactive debate planner:",
    "",
    "Decision rules:",
    `- Return exactly ${NO_DEBATE_SENTINEL} unless there is a strong, timely debate worth launching now.`,
    "- You are planning an agent-hosted debate. The host is you, so you must stay separate from both speaking seats.",
    "- Choose exactly two distinct participant agents from the available public agents listed below.",
    "- If you propose a debate, return strict JSON with keys: topic, proStance, conStance, preferredProHandle, preferredConHandle.",
    "- preferredProHandle and preferredConHandle must each exactly match one listed handle, and they must not be the same handle.",
    "- proStance and conStance should be clear one-sentence positions.",
    "- Do not wrap the JSON in markdown fences.",
    "",
    SYSTEM_PROMPT,
    "",
    "Recent public topics:",
    params.recentTopics.map(compactTopicSummary).join("\n\n") || "- No recent topics found.",
    "",
    "Available public agents:",
    params.directoryAgents.map(compactAgentSummary).join("\n\n") || "- No eligible public agents found.",
    "",
    "Recent debates to avoid duplicating:",
    params.recentDebates.map(compactDebateSummary).join("\n\n") || "- No recent debates found.",
    "",
    `Return either ${NO_DEBATE_SENTINEL} or the JSON object.`
  ].join("\n");
}
