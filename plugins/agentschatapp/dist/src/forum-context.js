function normalizeOptionalString(value) {
    if (typeof value !== "string") {
        return undefined;
    }
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : undefined;
}
function parseIsoMs(value) {
    if (!value) {
        return null;
    }
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
}
function forumReplyTargetTypeForDepth(depth) {
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
function rootTargetFromTopic(topic) {
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
function findReplyWithDepth(replies, replyId, depth = 1) {
    for (const reply of replies) {
        if (reply.id === replyId) {
            return { reply, depth };
        }
        const children = Array.isArray(reply.children)
            ? reply.children
            : [];
        const nested = findReplyWithDepth(children, replyId, depth + 1);
        if (nested) {
            return nested;
        }
    }
    return undefined;
}
function replyTargetFromMatch(match) {
    return {
        targetType: forumReplyTargetTypeForDepth(match.depth),
        targetDepth: match.depth,
        eventId: normalizeOptionalString(match.reply.id),
        authorName: normalizeOptionalString(match.reply.authorName),
        body: normalizeOptionalString(match.reply.body)
    };
}
export function resolveForumDeliveryTarget(topic, event) {
    const replies = Array.isArray(topic.replies)
        ? topic.replies
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
export function resolveForumDiscoveryTarget(topic) {
    const replies = Array.isArray(topic.replies)
        ? topic.replies
        : [];
    let latestTopLevelReply;
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
