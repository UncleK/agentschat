import { test } from "node:test";
import assert from "node:assert/strict";
import { threadTone, visibleThreads } from "../lib/chat.ts";
import type { Thread } from "../lib/client-api.ts";

const threads: Thread[] = [
  {
    threadId: "m",
    counterpart: { id: "m", displayName: "Muse", isOnline: true },
    lastMessage: { preview: "Newest", occurredAt: "2026-09-13" },
    unreadCount: 0,
  },
  {
    threadId: "a",
    counterpart: { id: "a", displayName: "Atlas", isOnline: false },
    lastMessage: { preview: "Oldest", occurredAt: "2026-09-11" },
    unreadCount: 0,
  },
  {
    threadId: "s",
    counterpart: {
      id: "s",
      displayName: "Syntax",
      handle: "syntax-agent",
      isOnline: true,
      viewerFollowsAgent: true,
      agentFollowsViewer: true,
    },
    lastMessage: {
      preview: "Reply",
      occurredAt: "2026-09-12",
      actor: { displayName: "对方管理员" },
    },
    unreadCount: 2,
  },
];
test("Flutter conversation ordering prioritizes unread, then name rather than activity", () => {
  assert.deepEqual(
    visibleThreads(threads, "").map((t) => t.threadId),
    ["s", "a", "m"],
  );
  assert.deepEqual(
    threads.map((t) => t.threadId),
    ["m", "a", "s"],
  );
});
test("presence and mutual follow determine distinct conversation colors", () => {
  assert.deepEqual(threads.map(threadTone), ["online", "offline", "mutual"]);
  assert.equal(
    threadTone({
      ...threads[2],
      counterpart: { ...threads[2].counterpart, isOnline: false },
    }),
    "offline",
  );
});
test("conversation search covers relationship, unread, handle and message author", () => {
  for (const search of [
    "互关",
    "未读",
    "syntax-agent",
    "对方管理员",
    " follows you ",
  ]) {
    assert.deepEqual(
      visibleThreads(threads, search).map((t) => t.threadId),
      ["s"],
    );
  }
  assert.deepEqual(
    visibleThreads(threads, "离线").map((t) => t.threadId),
    ["a"],
  );
  assert.deepEqual(
    visibleThreads(threads, "ONLINE").map((t) => t.threadId),
    ["s", "m"],
  );
});
