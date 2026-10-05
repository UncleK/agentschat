import test from "node:test";
import assert from "node:assert/strict";
import { forumStructuredData } from "../lib/forum-schema.ts";
import { jsonLd } from "../lib/proxy-policy.ts";
import type { Reply, Topic } from "../lib/public-api.ts";

const reply = (fields: Partial<Reply>): Reply => ({
  id: "reply-id",
  authorName: "Same display name",
  authorHandle: "other-agent",
  body: "Reply body",
  occurredAt: "2026-10-06T00:00:00Z",
  likeCount: 0,
  viewerHasLiked: false,
  isHuman: false,
  replyCount: 0,
  children: [],
  ...fields,
});
const topic = (fields: Partial<Topic> = {}): Topic => ({
  threadId: "topic-id",
  rootEventId: "root-id",
  title: "Topic title",
  summary: "Topic body",
  rootBody: "Topic body",
  authorName: "Same display name",
  authorHandle: "topic-agent",
  replyCount: 0,
  viewCount: 0,
  participantCount: 1,
  followCount: 0,
  hotScore: 0,
  isHot: false,
  tags: [],
  createdAt: "2026-10-06T00:00:00Z",
  lastActivityAt: "2026-10-06T00:00:00Z",
  replies: [],
  ...fields,
});

test("forum authors use distinct profile handles even when names match, including nested replies", () => {
  const schema = forumStructuredData(
    topic({
      replies: [reply({ children: [reply({ authorHandle: "third-agent" })] })],
    }),
    "https://agentschat.app",
  );
  assert.equal(schema.author.url, "https://agentschat.app/agents/topic-agent");
  assert.equal(
    schema.comment[0].author.url,
    "https://agentschat.app/agents/other-agent",
  );
  assert.equal(
    schema.comment[0].comment![0].author.url,
    "https://agentschat.app/agents/third-agent",
  );
});

test("missing public profiles and human authors never get a guessed agent profile URL", () => {
  const schema = forumStructuredData(
    topic({
      authorHandle: null,
      replies: [reply({ authorHandle: null }), reply({ isHuman: true })],
    }),
    "https://agentschat.app",
  );
  assert.equal(schema.author.url, undefined);
  assert.equal(schema.comment[0].author.url, undefined);
  assert.equal(schema.comment[1].author["@type"], "Person");
  assert.equal(schema.comment[1].author.url, undefined);
});

test("profile path encoding and JSON-LD escaping preserve authored text without script injection", () => {
  const body = '</script><script>alert("authored text")</script>';
  const schema = forumStructuredData(
    topic({ authorHandle: "agent name", rootBody: body }),
    "https://agentschat.app",
  );
  assert.equal(schema.author.url, "https://agentschat.app/agents/agent%20name");
  const serialized = jsonLd(schema);
  assert.ok(!serialized.includes("</script>"));
  assert.equal((JSON.parse(serialized) as typeof schema).text, body);
});
