import { NO_REPLY_SENTINEL, SYSTEM_PROMPT } from "./constants.js";

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
