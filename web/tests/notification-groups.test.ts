import { test } from "node:test";
import assert from "node:assert/strict";
import { groupNotices, noticeSection } from "../lib/notification-groups.ts";
import type { Agent, Notice } from "../lib/client-api.ts";
const agents = [{ id: "mine", displayName: "Aether" }] as Agent[];
test("notification URL only accepts own section keys", () => {
  assert.equal(noticeSection("hub"), "hub");
  assert.equal(noticeSection("constructor"), "all");
  assert.equal(noticeSection("toString"), "all");
  assert.equal(noticeSection("unknown"), "all");
});
const notice = (
  id: string,
  payload: Notice["payload"],
  extra = {},
): Notice => ({
  id,
  kind: "dm.received",
  threadId: "thread",
  createdAt: id,
  payload,
  ...extra,
});
test("owned-agent commands and network messages keep identity boundaries", () => {
  const items = [
    notice("1", {
      targetType: "human",
      targetId: "me",
      actorAgentId: "mine",
    }),
    notice("2", {
      targetType: "agent",
      targetId: "mine",
      actorAgentId: "peer",
    }),
    notice("3", { targetType: "agent", targetId: "mine", actorUserId: "me" }),
    notice("4", {
      targetType: "agent",
      targetId: "mine",
      actorAgentId: "mine",
    }),
    notice("5", {
      targetType: "human",
      targetId: "me",
      actorAgentId: "peer",
    }),
    notice("6", {
      targetType: "agent",
      targetId: "other",
      actorAgentId: "peer",
    }),
  ];
  assert.deepEqual(
    groupNotices(items, "hub", agents, "mine", "me").flatMap(
      (g) => g.unreadIds,
    ),
    ["1"],
  );
  assert.deepEqual(
    groupNotices(items, "chat", agents, "mine", "me").flatMap(
      (g) => g.unreadIds,
    ),
    ["2"],
  );
});
test("forum groups unread branches and does not mark hidden notices", () => {
  const items = [
    notice("1", {}, { kind: "forum.reply" }),
    notice("2", {}, { kind: "forum.reply" }),
    notice("3", {}, { kind: "forum.reply", readAt: "now" }),
    notice("4", {}),
  ];
  const groups = groupNotices(items, "forum", agents, "mine", "me");
  assert.equal(groups.length, 1);
  assert.equal(groups[0].latest.id, "2");
  assert.deepEqual(groups[0].unreadIds, ["2", "1"]);
});
test("latest debate state hides ended or paused sessions even when earlier notices are unread", () => {
  const items = [
    notice(
      "1",
      { targetId: "debate", eventType: "debate.started" },
      { kind: "debate.activity" },
    ),
    notice(
      "2",
      { targetId: "debate", eventType: "debate.ended" },
      { kind: "debate.activity", readAt: "now" },
    ),
  ];
  assert.equal(groupNotices(items, "live", agents, "mine", "me").length, 0);
  assert.equal(
    groupNotices(items.slice(0, 1), "live", agents, "mine", "me").length,
    1,
  );
});
