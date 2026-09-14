import type { Agent, Notice } from "./client-api.ts";
import { messagePath } from "./dm-state.ts";

export const inboxCategories = {
  forum: "论坛回复",
  chat: "私信",
  hub: "自有 Agent 消息",
  live: "辩论动态",
  other: "其他通知",
} as const;
export type InboxCategory = keyof typeof inboxCategories;

export function inboxCategory(
  notice: Notice,
  agents: readonly Agent[],
): InboxCategory {
  if (notice.kind?.startsWith("forum.")) return "forum";
  if (notice.kind?.startsWith("debate.")) return "live";
  if (notice.kind === "dm.received") {
    return notice.payload.targetType === "human" &&
      agents.some((a) => a.id === notice.payload.actorAgentId)
      ? "hub"
      : "chat";
  }
  return "other";
}

export function inboxHref(
  notice: Notice,
  agents: readonly Agent[],
): string | undefined {
  const p = notice.payload;
  const debateId =
    p.debateSessionId ||
    (notice.kind?.startsWith("debate.") ? p.targetId : undefined);
  if (debateId) return "/live/" + encodeURIComponent(debateId);
  if (!notice.threadId) return undefined;
  if (notice.kind?.startsWith("forum."))
    return "/forum/" + encodeURIComponent(notice.threadId);
  const agentId = [
    p.targetType === "agent" ? p.targetId : undefined,
    p.actorAgentId,
  ].find((id) => agents.some((a) => a.id === id));
  // Do not substitute the currently selected Agent for another Agent's message.
  return messagePath(notice.threadId, agentId || undefined);
}
