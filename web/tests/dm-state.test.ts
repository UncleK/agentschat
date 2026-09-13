import { test } from "node:test";
import assert from "node:assert/strict";
import {
  bridgeMessageGap,
  chooseActiveAgent,
  mergeMessages,
  messagePath,
  nextThreadCursor,
  assertActiveThread,
} from "../lib/dm-state.ts";
import { authPath, safeReturnPath } from "../lib/auth-navigation.ts";
import { messageRole } from "../lib/dm-roles.ts";

const range = (first: number, last: number) =>
  Array.from({ length: last - first + 1 }, (_, index) => {
    const id = first + index;
    return {
      eventId: String(id),
      occurredAt: new Date(id * 1000).toISOString(),
      content: String(id),
    };
  });
test("conversation-list backlog reopens pagination without undoing later page progress", () => {
  const threads = (first: number, last: number) =>
    range(first, last).map((message) => ({
      threadId: message.eventId,
      lastMessage: { occurredAt: message.occurredAt },
    }));
  const previous = threads(1, 40),
    incoming = threads(91, 140);
  assert.equal(nextThreadCursor(previous, incoming, null, "91"), "91");
  assert.equal(
    nextThreadCursor([...incoming, ...previous], incoming, "41", "91"),
    "41",
  );
  assert.equal(nextThreadCursor(previous, threads(1, 40), null, null), null);
  const sameTime = [
    { threadId: "old", lastMessage: { occurredAt: "2026-01-01T00:00:00Z" } },
  ];
  assert.equal(
    nextThreadCursor(
      sameTime,
      [{ ...sameTime[0], threadId: "new" }],
      null,
      "tie",
    ),
    "tie",
  );
});
test("background backlog is bridged even when the initial history was complete", async () => {
  const previous = range(1, 40),
    cursors: string[] = [];
  const latest = { messages: range(91, 140), nextCursor: "91" };
  const result = await bridgeMessageGap(previous, latest, async (cursor) => {
    cursors.push(cursor);
    return cursor === "91"
      ? { messages: range(41, 90), nextCursor: "41" }
      : { messages: range(1, 40), nextCursor: null };
  });
  assert.deepEqual(cursors, ["91", "41"]);
  assert.deepEqual(
    mergeMessages(previous, result.messages).map((message) =>
      Number(message.eventId),
    ),
    Array.from({ length: 140 }, (_, index) => index + 1),
  );
});
test("gap fetching stops at an existing anchor without traversing all older history", async () => {
  const cursors: string[] = [];
  const result = await bridgeMessageGap(
    range(51, 100),
    { messages: range(171, 220), nextCursor: "171" },
    async (cursor) => {
      cursors.push(cursor);
      const newest = Number(cursor) - 1;
      return {
        messages: range(newest - 49, newest),
        nextCursor: String(newest - 49),
      };
    },
  );
  assert.deepEqual(cursors, ["171", "121"]);
  assert.equal(mergeMessages(range(51, 100), result.messages).length, 170);
});
test("first page keeps its pagination cursor; overlapping updates do not fetch", async () => {
  const load = async () => {
    assert.fail("Unexpected extra history request");
  };
  const initial = await bridgeMessageGap(
    [],
    { messages: range(51, 100), nextCursor: "51" },
    load,
  );
  assert.equal(initial.nextCursor, "51");
  await bridgeMessageGap(
    range(51, 100),
    { messages: range(81, 130), nextCursor: "81" },
    load,
  );
});
test("repeated pagination cursors fail explicitly instead of looping forever", async () => {
  await assert.rejects(
    bridgeMessageGap(
      range(1, 2),
      { messages: range(101, 150), nextCursor: "same" },
      async () => ({ messages: range(51, 100), nextCursor: "same" }),
    ),
    /重复/,
  );
});
test("fresh message fields replace stale cached fields and equal timestamps stay ordered", () => {
  const old = [
    { eventId: "b", occurredAt: "2026-01-01T00:00:00Z", content: "old" },
  ];
  const merged = mergeMessages(old, [
    { ...old[0], content: "new" },
    { ...old[0], eventId: "a" },
  ]);
  assert.deepEqual(
    merged.map((message) => message.eventId),
    ["a", "b"],
  );
  assert.equal(merged[1].content, "new");
});
test("only an owned available Agent can be restored from saved selection", () => {
  const agents = [
    { id: "A" },
    { id: "B" },
    { id: "suspended", status: "suspended" },
  ];
  assert.equal(chooseActiveAgent(agents, "B", "A"), "B");
  assert.equal(chooseActiveAgent(agents, "outsider", "suspended", "A"), "A");
});
test("thread access checks only the active Agent without falling back to another owned Agent", async () => {
  const calls: string[] = [];
  await assert.rejects(
    assertActiveThread("A", async (id) => {
      calls.push(id);
      if (id === "A") throw { status: 404 };
    }),
    /当前激活的 Agent/,
  );
  assert.deepEqual(calls, ["A"]);
  await assertActiveThread("B", async (id) => {
    assert.equal(id, "B");
  });
  await assert.rejects(
    assertActiveThread("A", async () => {
      throw new Error("Server unavailable");
    }),
    /Server unavailable/,
  );
});
test("switching login and register retains thread and Agent context", () => {
  const destination = messagePath("thread/id", "B");
  const login = new URL(authPath("login", destination), "https://site.test");
  const registration = new URL(
    authPath("register", login.searchParams.get("next")),
    login,
  );
  assert.equal(registration.searchParams.get("next"), destination);
  assert.equal(
    safeReturnPath(registration.searchParams.get("next")),
    destination,
  );
  for (const invalid of [
    "https://evil.test",
    "//evil.test",
    "/messages\\evil.test",
    "/messages\n",
  ])
    assert.equal(safeReturnPath(invalid), null);
});
test("message identities distinguish four parties while sharing one real owner", () => {
  const members = [
    { type: "agent", id: "A", ownerUserId: "ownerA" },
    { type: "agent", id: "B", ownerUserId: "ownerB" },
  ];
  assert.equal(
    messageRole({ type: "agent", id: "A" }, members, "A", "ownerA").key,
    "local-agent",
  );
  assert.equal(
    messageRole({ type: "agent", id: "B" }, members, "A", "ownerA").key,
    "remote-agent",
  );
  assert.deepEqual(
    messageRole({ type: "human", id: "ownerA" }, members, "A", "ownerA"),
    { key: "local-human", label: "我" },
  );
  assert.deepEqual(
    messageRole({ type: "human", id: "ownerB" }, members, "A", "ownerA"),
    { key: "remote-human", label: "对方管理员" },
  );
  assert.equal(
    messageRole({ type: "human", id: "formerOwner" }, members, "A", "ownerA")
      .label,
    "历史参与者",
  );
  assert.equal(
    messageRole({ type: "system", id: "system" }, members, "A", "ownerA").label,
    "系统",
  );
  assert.equal(
    messageRole({ type: "unknown", id: "unknown" }, members, "A", "ownerA")
      .label,
    "未知身份",
  );
  assert.equal(
    messageRole(
      { type: "human", id: "ownerA" },
      [members[0], { ...members[1], ownerUserId: "ownerA" }],
      "A",
      "ownerA",
    ).label,
    "我（双方管理员）",
  );
});
