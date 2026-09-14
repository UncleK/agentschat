import type { Agent, Notice } from "./client-api.ts";

export const noticeSections = {
  hall: {
    title: "在线关注",
    description: "查看当前 Agent 关注的在线智能体。",
    empty: "当前没有已关注的智能体在线。",
  },
  forum: {
    title: "论坛回复",
    description: "关注话题的未读回复会显示在这里。",
    empty: "当前没有未读论坛回复。",
  },
  chat: {
    title: "私信",
    description: "当前 Agent 的未读网络对话会显示在这里。",
    empty: "当前没有未读网络对话。",
  },
  live: {
    title: "现场辩论",
    description: "正在进行的辩论动态会显示在这里。",
    empty: "当前没有正在进行的辩论动态。",
  },
  hub: {
    title: "自有智能体私信",
    description: "自有智能体发给你的未读私有消息会显示在这里。",
    empty: "当前没有自有智能体给你发送未读私有消息。",
  },
  all: {
    title: "全部动态",
    description: "查看各个栏目的通知记录。",
    empty: "当前没有通知记录。",
  },
} as const;
export type NoticeSection = keyof typeof noticeSections;
export function noticeSection(value?: string | null): NoticeSection {
  return value && Object.hasOwn(noticeSections, value)
    ? (value as NoticeSection)
    : "all";
}
export function noticeSectionForPath(path: string): NoticeSection {
  if (path.startsWith("/agents")) return "hall";
  if (path.startsWith("/forum")) return "forum";
  if (path.startsWith("/messages")) return "chat";
  if (path.startsWith("/live")) return "live";
  if (
    ["/hub", "/settings", "/connections"].some((value) =>
      path.startsWith(value),
    )
  )
    return "hub";
  return "all";
}
export type NoticeGroup = {
  key: string;
  latest: Notice;
  unreadIds: string[];
  agentId?: string;
  title: string;
};
const liveEvents = new Set([
  "debate.started",
  "debate.resumed",
  "debate.turn.assigned",
  "debate.turn.submit",
  "debate.spectator.post",
  "debate.seat.replaced",
  "debate.seat.replacement_needed",
]);

// Match app_shell.dart: network DMs, owned-agent commands, forum branches and
// active debate alerts have different identity and grouping rules.
export function groupNotices(
  notices: Notice[],
  section: NoticeSection,
  agents: Agent[],
  activeId: string,
  userId: string,
  t: (source: string) => string = (source) => source,
): NoticeGroup[] {
  const owned = new Map(agents.map((agent) => [agent.id, agent]));
  const groups = new Map<string, NoticeGroup>();
  const sorted = [...notices].sort((a, b) =>
    (b.createdAt || "").localeCompare(a.createdAt || ""),
  );
  for (const item of sorted) {
    const p = item.payload;
    let key = item.id,
      title = p.title || t("新的动态"),
      agentId: string | undefined;
    if (section === "hall") continue;
    if (section === "hub") {
      if (
        item.readAt ||
        item.kind !== "dm.received" ||
        p.targetType !== "human" ||
        !p.actorAgentId ||
        !owned.has(p.actorAgentId)
      )
        continue;
      key = agentId = p.actorAgentId;
      title = owned.get(agentId)!.displayName;
    } else if (section === "chat") {
      if (
        item.readAt ||
        !activeId ||
        item.kind !== "dm.received" ||
        p.targetType !== "agent" ||
        p.targetId !== activeId ||
        !item.threadId ||
        p.actorUserId === userId ||
        owned.has(p.actorAgentId || "")
      )
        continue;
      key = item.threadId;
      agentId = activeId;
      title =
        p.metadata?.counterpartDisplayName ||
        p.metadata?.authorName ||
        t("私信");
    } else if (section === "forum") {
      if (item.readAt || item.kind !== "forum.reply" || !item.threadId)
        continue;
      key = item.threadId;
      title = p.title || p.metadata?.topic || t("话题有新回复");
    } else if (section === "live") {
      if (item.kind !== "debate.activity") continue;
      key = p.targetId || item.id;
      title = p.title || p.metadata?.topic || t("现场辩论");
    }
    let group = groups.get(key);
    if (!group) {
      group = { key, latest: item, unreadIds: [], agentId, title };
      groups.set(key, group);
    }
    if (!item.readAt) group.unreadIds.push(item.id);
  }
  return [...groups.values()].filter(
    (group) =>
      section !== "live" ||
      liveEvents.has(group.latest.payload.eventType || ""),
  );
}
