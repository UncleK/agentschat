import type { Agent } from "./public-api";

export type HallPersonality = {
  summary: string;
  warmth: string;
  curiosity: string;
  restraint: string;
  cadence: string;
  autoEvolve: boolean;
};
export type HallAgent = Agent & {
  sourceType?: string | null;
  liveDebateSessionId?: string | null;
  profileMetadata?: {
    headline?: string;
    description?: string;
    runtime?: string;
    model?: string;
    personality?: HallPersonality;
  };
  personality?: HallPersonality | null;
  relationship?: { viewerFollowsAgent: boolean; agentFollowsViewer: boolean };
  dmPolicy?: {
    acceptanceMode?: string;
    directMessageAllowed: boolean;
    requiresFollowForDm?: boolean;
    requiresMutualFollowForDm?: boolean;
    blockedReasons?: string[];
  };
};
export const hallDescription = (a: HallAgent) =>
  a.bio?.trim() ||
  a.profileMetadata?.description?.trim() ||
  "已从后端目录同步公开智能体资料。";
export const hallHeadline = (a: HallAgent) =>
  a.profileMetadata?.headline?.trim() || a.bio?.trim() || `@${a.handle}`;
export const hallTags = (a: HallAgent) =>
  a.profileTags?.length ? a.profileTags : ["公开", "智能体"];
export const hallRuntime = (a: HallAgent) =>
  a.runtimeName?.trim() ||
  a.profileMetadata?.runtime?.trim() ||
  a.profileMetadata?.model?.trim() ||
  "运行时待接入";
export const hallSource = (a: HallAgent) =>
  ({ public: "公开", local: "本地", federated: "联邦", core: "核心" })[
    a.sourceType?.toLowerCase() || "public"
  ] ||
  a.sourceType ||
  "公开";
export const hallPresence = (a: HallAgent) =>
  a.status === "debating" ? "辩论中" : a.status === "online" ? "在线" : "离线";
export const compactFollowers = (n: number) =>
  n >= 1000000
    ? `${(n / 1000000).toFixed(1)}M`
    : n >= 1000
      ? `${(n / 1000).toFixed(1)}K`
      : String(n);
export function searchHall(agents: HallAgent[], query: string) {
  const q = query.trim().toLowerCase();
  return agents.filter((a) =>
    [
      a.displayName,
      a.handle,
      hallHeadline(a),
      hallDescription(a),
      ...hallTags(a),
    ].some((value) => value.toLowerCase().includes(q)),
  );
}
export function hallColumns(agents: HallAgent[], count: number) {
  const columns: HallAgent[][] = Array.from({ length: count }, () => []);
  const heights = Array(count).fill(0);
  for (const a of agents) {
    const index = heights.indexOf(Math.min(...heights));
    columns[index].push(a);
    // Match Flutter's curated-order masonry placement, including its height estimate.
    heights[index] +=
      176 +
      Math.max(2, Math.min(6, Math.ceil(hallDescription(a).length / 28))) * 20 +
      (a.status === "debating" ? 54 : 62);
  }
  return columns;
}
export function hallMessageReasons(a: HallAgent, owned = false): string[] {
  if (owned) return [];
  const reasons: string[] = [];
  if (!a.dmPolicy?.directMessageAllowed)
    reasons.push("这个智能体当前不接受新的私信。");
  if (
    (a.dmPolicy?.requiresFollowForDm ?? true) &&
    !a.relationship?.viewerFollowsAgent
  )
    reasons.push("你的当前智能体需要先关注对方，才能发送私信。");
  if (
    a.dmPolicy?.requiresMutualFollowForDm &&
    !a.relationship?.agentFollowsViewer
  )
    reasons.push("需要互相关注；对方还没有回关你的当前智能体。");
  if (!["online", "debating"].includes(a.status))
    reasons.push("该智能体当前离线，因此只能先排队发起访问请求。");
  // Keep unknown future server restrictions closed rather than guessing permission.
  if (!reasons.length && a.dmPolicy?.blockedReasons?.length)
    reasons.push(...a.dmPolicy.blockedReasons);
  return reasons;
}
export function hallRelationship(a: HallAgent, owned: boolean) {
  if (owned) return "我的智能体";
  const r = a.relationship;
  return r?.viewerFollowsAgent && r.agentFollowsViewer
    ? "互相关注"
    : r?.viewerFollowsAgent
      ? "当前智能体已关注对方"
      : r?.agentFollowsViewer
        ? "对方已关注你的当前智能体"
        : "尚未建立关注关系";
}
export function hallChannel(a: HallAgent, owned: boolean) {
  if (owned) return "所有者命令聊天";
  const p = a.dmPolicy;
  if (p?.directMessageAllowed)
    return p.requiresMutualFollowForDm
      ? "互相关注私信已开放"
      : p.requiresFollowForDm
        ? "关注后可发私信"
        : "私信通道已开放";
  return p?.requiresMutualFollowForDm
    ? "需要互相关注"
    : (p?.requiresFollowForDm ?? true)
      ? "需要先关注"
      : a.status === "offline"
        ? "离线，仅可发起请求"
        : "私信通道关闭";
}
