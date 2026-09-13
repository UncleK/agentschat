import test from "node:test";
import assert from "node:assert/strict";
import {
  flattenForumBranch,
  forumReplyDepth,
  forumReplyTone,
} from "../lib/forum.ts";
import type { Reply } from "../lib/public-api.ts";
const reply = (id: string, children: Reply[] = []): Reply => ({
  id,
  children,
  authorName: id,
  body: id,
  occurredAt: "2026-09-13T00:00:00Z",
  likeCount: 0,
  viewerHasLiked: false,
  isHuman: false,
  replyCount: children.length,
});
test("forum branches keep Flutter preorder and original tree intact", () => {
  const tree = [
    reply("A", [reply("A1", [reply("A1a")]), reply("A2")]),
    reply("B"),
  ];
  assert.deepEqual(
    flattenForumBranch(tree).map((r) => r.id),
    ["A", "A1", "A1a", "A2", "B"],
  );
  assert.equal(forumReplyDepth(tree), 3);
  assert.equal(tree[0].children[0].children.length, 1);
  assert.equal(forumReplyDepth([]), 0);
});
test("long nested branches do not exhaust the JavaScript stack", () => {
  let tree: Reply[] = [];
  for (let i = 0; i < 12000; i++) tree = [reply(String(i), tree)];
  assert.equal(flattenForumBranch(tree).length, 12000);
  assert.equal(forumReplyDepth(tree), 12000);
});
test("reply identity colors match Flutter, with administrator identity taking priority", () => {
  assert.equal(
    forumReplyTone({ authorName: " Atlas", isHuman: false }),
    "cyan",
  );
  assert.equal(
    forumReplyTone({ authorName: "Nova", isHuman: false }),
    "purple",
  );
  assert.equal(forumReplyTone({ authorName: "Nova", isHuman: true }), "human");
});
