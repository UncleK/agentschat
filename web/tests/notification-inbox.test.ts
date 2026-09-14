import { test } from "node:test";
import assert from "node:assert/strict";
import { inboxCategory, inboxHref } from "../lib/notification-inbox.ts";
import type { Agent, Notice } from "../lib/client-api.ts";

const agents = [{ id: "mine-a" }, { id: "mine-b" }] as Agent[];
const dm = (payload: Notice["payload"]): Notice => ({
  id: "notice",
  kind: "dm.received",
  threadId: "thread",
  payload,
});

test("global inbox includes messages for every owned agent without conflating human and agent recipients", () => {
  for (const id of ["mine-a", "mine-b"]) {
    const message = dm({
      targetType: "agent",
      targetId: id,
      actorAgentId: "peer",
    });
    assert.equal(inboxCategory(message, agents), "chat");
    assert.equal(inboxHref(message, agents), `/messages/thread?agent=${id}`);
  }
  const ownerMessage = dm({ targetType: "human", actorAgentId: "mine-b" });
  assert.equal(inboxCategory(ownerMessage, agents), "hub");
  assert.equal(
    inboxHref(ownerMessage, agents),
    "/messages/thread?agent=mine-b",
  );
  assert.equal(
    inboxCategory(dm({ targetType: "human", actorAgentId: "peer" }), agents),
    "chat",
  );
});

test("read history and finished debates stay categorized in the global inbox", () => {
  const topic: Notice = {
    id: "reply",
    kind: "forum.reply",
    threadId: "topic",
    readAt: "now",
    payload: {},
  };
  assert.equal(inboxCategory(topic, agents), "forum");
  assert.equal(inboxHref(topic, agents), "/forum/topic");
  const ended: Notice = {
    id: "end",
    kind: "debate.activity",
    payload: { targetId: "debate", eventType: "debate.ended" },
  };
  assert.equal(inboxCategory(ended, agents), "live");
  assert.equal(inboxHref(ended, agents), "/live/debate");
  assert.equal(
    inboxCategory({ id: "new", kind: "new.kind", payload: {} }, agents),
    "other",
  );
});

test("inbox links never borrow an unrelated active identity or invent a target", () => {
  assert.equal(
    inboxHref(
      dm({ targetType: "agent", targetId: "unknown", actorAgentId: "peer" }),
      agents,
    ),
    "/messages/thread",
  );
  assert.equal(inboxHref({ id: "unknown", payload: {} }, agents), undefined);
});
