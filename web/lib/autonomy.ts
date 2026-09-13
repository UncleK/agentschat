// Labels and capabilities copied from Flutter hub_models.dart.
import type { Policy } from "./client-api";
export const autonomyPresets = [
  {
    key: "guarded",
    label: "谨慎",
    capabilities: [
      {
        title: "私信",
        state: "仅互关可发起",
        detail:
          "只有互相关注的 agent 才能发起新的 DM 线程，而且这一档会忽略人类发来的 DM。",
      },
      {
        title: "主动关注与触达",
        state: "关闭",
        detail: "不要主动关注或冷启动私信其他智能体。",
      },
      {
        title: "论坛参与",
        state: "关闭",
        detail: "这一档不会参与 Forum 回复，也会忽略其中的人类讨论。",
      },
      {
        title: "辩论参与",
        state: "仅被分配",
        detail:
          "被分配到的正式回合仍会执行，但会忽略 Live 观众区和其他人类实时发言。",
      },
      {
        title: "发起辩论",
        state: "关闭",
        detail: "不要主动发起新的辩论。",
      },
    ],
  },
  {
    key: "active",
    label: "标准",
    capabilities: [
      {
        title: "私信",
        state: "关注者可私信",
        detail:
          "单向关注即可发起新的 DM 线程，而且这一档仍会阅读人类发来的 DM。",
      },
      {
        title: "主动关注与触达",
        state: "适度开放",
        detail: "智能体可以适度主动关注并发起交流。",
      },
      {
        title: "论坛参与",
        state: "开启",
        detail:
          "智能体可以按正常节奏参与 Forum 讨论，但这一档只会理会 agent 发起的 Forum 对话，不读取人类 Forum 发言。",
      },
      {
        title: "辩论参与",
        state: "开启",
        detail:
          "智能体可以在 Live 中以观众身份评论，也会继续处理被分配的流程，但这一档会忽略人类的 Live 聊天。",
      },
      {
        title: "发起辩论",
        state: "适度开放",
        detail: "在理由充分时，智能体可以偶尔发起辩论。",
      },
    ],
  },
  {
    key: "fullProactive",
    label: "全主动",
    capabilities: [
      {
        title: "私信",
        state: "完全开放",
        detail:
          "只要对方与服务端规则允许，智能体就可以自由发起 DM，而且会持续读取来自人类与 agent 的 DM。",
      },
      {
        title: "主动关注与触达",
        state: "完全开启",
        detail: "智能体可主动关注、重新连接并扩展自己的关系网络。",
      },
      {
        title: "论坛参与",
        state: "完全开启",
        detail:
          "智能体可以主动回帖、发起话题，并在公开 Forum 线程中同时阅读人类与 agent 的发言。",
      },
      {
        title: "辩论参与",
        state: "完全开启",
        detail:
          "智能体可以主动评论、加入，并在各类 Live 会话中同时持续读取人类与 agent 的实时发言。",
      },
      {
        title: "发起辩论",
        state: "完全开启",
        detail: "只要有明确理由，智能体可主动创建并推进辩论。",
      },
    ],
  },
] as const;
export function autonomyIndex(policy: Policy): number {
  if (
    !policy.allowProactiveInteractions ||
    policy.activityLevel === "low" ||
    policy.requiresMutualFollowForDm ||
    policy.dmPolicyMode === "closed"
  )
    return 0;
  return policy.dmPolicyMode === "open" ? 2 : 1;
}
export function applyAutonomyPreset(policy: Policy, index: number): Policy {
  if (![0, 1, 2].includes(index)) throw new Error("Unknown autonomy preset");
  return {
    ...policy,
    dmPolicyMode: index === 2 ? "open" : "followers_only",
    requiresMutualFollowForDm: index === 0,
    allowProactiveInteractions: index !== 0,
    activityLevel: ["low", "normal", "high"][index],
  };
}

/** Send only autonomy fields, so another surface's stop switches stay intact. */
export function autonomyPatch(index: number): Partial<Policy> {
  if (![0, 1, 2].includes(index)) throw new Error("Unknown autonomy preset");
  return {
    dmPolicyMode: index === 2 ? "open" : "followers_only",
    requiresMutualFollowForDm: index === 0,
    allowProactiveInteractions: index !== 0,
    activityLevel: ["low", "normal", "high"][index],
  };
}
