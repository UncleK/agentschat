export type ForumReplyTargetType =
  | "topic_root"
  | "first_level_reply"
  | "second_level_reply"
  | "unknown";

export type ForumReplyTargetContext = {
  targetType: ForumReplyTargetType;
  targetDepth: number | null;
  eventId?: string;
  authorName?: string;
  body?: string;
};

function normalizeOptionalString(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function parseIsoMs(value?: string | null): number | null {
  if (!value) {
    return null;
  }
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? null : parsed;
}

function forumReplyTargetTypeForDepth(depth: number | null): ForumReplyTargetType {
  if (depth === 0) {
    return "topic_root";
  }
  if (depth === 1) {
    return "first_level_reply";
  }
  if (depth === 2) {
    return "second_level_reply";
  }
  return "unknown";
}

function rootTargetFromTopic(topic: Record<string, unknown>): ForumReplyTargetContext | null {
  const rootEventId = normalizeOptionalString(topic.rootEventId);
  if (!rootEventId) {
    return null;
  }
  return {
    targetType: "topic_root",
    targetDepth: 0,
    eventId: rootEventId,
    authorName: normalizeOptionalString(topic.authorName),
    body: normalizeOptionalString(topic.rootBody)
  };
}

function findReplyWithDepth(
  replies: Record<string, unknown>[],
  replyId: string,
  depth = 1
): { reply: Record<string, unknown>; depth: number } | undefined {
  for (const reply of replies) {
    if (reply.id === replyId) {
      return { reply, depth };
    }
    const children = Array.isArray(reply.children)
      ? (reply.children as Record<string, unknown>[])
      : [];
    const nested = findReplyWithDepth(children, replyId, depth + 1);
    if (nested) {
      return nested;
    }
  }
  return undefined;
}

function replyTargetFromMatch(
  match: { reply: Record<string, unknown>; depth: number }
): ForumReplyTargetContext {
  return {
    targetType: forumReplyTargetTypeForDepth(match.depth),
    targetDepth: match.depth,
    eventId: normalizeOptionalString(match.reply.id),
    authorName: normalizeOptionalString(match.reply.authorName),
    body: normalizeOptionalString(match.reply.body)
  };
}

export function resolveForumDeliveryTarget(
  topic: Record<string, unknown>,
  event: Record<string, unknown>
): ForumReplyTargetContext {
  const replies = Array.isArray(topic.replies)
    ? (topic.replies as Record<string, unknown>[])
    : [];
  const eventId = normalizeOptionalString(event.id);
  if (eventId) {
    const exactMatch = findReplyWithDepth(replies, eventId);
    if (exactMatch) {
      return replyTargetFromMatch(exactMatch);
    }
  }

  const parentEventId = normalizeOptionalString(event.parentEventId);
  if (parentEventId) {
    const rootEventId = normalizeOptionalString(topic.rootEventId);
    if (rootEventId && parentEventId === rootEventId) {
      return rootTargetFromTopic(topic) ?? {
        targetType: "topic_root",
        targetDepth: 0,
        eventId: rootEventId
      };
    }
    const parentMatch = findReplyWithDepth(replies, parentEventId);
    if (parentMatch) {
      return replyTargetFromMatch(parentMatch);
    }
  }

  return {
    targetType: "unknown",
    targetDepth: null,
    eventId,
    authorName: normalizeOptionalString(event.actorDisplayName),
    body: normalizeOptionalString(event.content)
  };
}

export function resolveForumDiscoveryTarget(
  topic: Record<string, unknown>
): ForumReplyTargetContext | null {
  const replies = Array.isArray(topic.replies)
    ? (topic.replies as Record<string, unknown>[])
    : [];
  let latestTopLevelReply: Record<string, unknown> | undefined;
  let latestTopLevelAt = -1;
  for (const reply of replies) {
    const occurredAt = parseIsoMs(normalizeOptionalString(reply.occurredAt)) ?? -1;
    if (occurredAt > latestTopLevelAt && normalizeOptionalString(reply.id)) {
      latestTopLevelAt = occurredAt;
      latestTopLevelReply = reply;
    }
  }

  if (latestTopLevelReply) {
    return {
      targetType: "first_level_reply",
      targetDepth: 1,
      eventId: normalizeOptionalString(latestTopLevelReply.id),
      authorName: normalizeOptionalString(latestTopLevelReply.authorName),
      body: normalizeOptionalString(latestTopLevelReply.body)
    };
  }

  return rootTargetFromTopic(topic);
}
