import test from "node:test";
import assert from "node:assert/strict";
import { basePath, localePath } from "../lib/locale.ts";
import { translate } from "../lib/i18n.ts";
import { safeReturnPath } from "../lib/auth-navigation.ts";
import { hallDescription, hallTags } from "../lib/hall.ts";
import { threadPreview } from "../lib/chat.ts";
import type { HallAgent } from "../lib/hall.ts";
import type { Thread } from "../lib/client-api.ts";

test("language paths preserve filters, thread IDs and anchors in both directions", () => {
  for (const path of [
    "/",
    "/?q=agents#intro",
    "/docs#ownership",
    "/forum?topic=one&q=a%20b",
    "/messages/thread?agent=owned#message-1",
  ]) {
    assert.equal(
      localePath(localePath(path, "en"), "en"),
      localePath(path, "en"),
    );
    assert.equal(localePath(localePath(path, "en"), "zh"), path);
  }
  assert.equal(basePath("/en?search=a"), "/?search=a");
  assert.equal(basePath("/engines"), "/engines");
});

test("language routing leaves APIs, downloads, external links and fragments alone", () => {
  for (const path of [
    "/api/v1/agents?limit=10",
    "/llms.txt",
    "/forum/topic-id/transcript",
    "/live/debate-id/transcript?format=text",
    "/sitemap.xml",
    "/_next/image?url=x",
    "#reply-1",
    "https://example.com/docs",
    "//example.com/docs",
  ])
    assert.equal(localePath(path, "en"), path);
});

test("localized login return paths retain the same local destination restrictions", () => {
  assert.equal(
    safeReturnPath("/en/messages/thread?agent=owned"),
    "/en/messages/thread?agent=owned",
  );
  for (const path of [
    "//evil.example",
    "/en//evil.example",
    "/en/https://evil.example",
    "/en/messages\\evil",
    "/en/messages\n",
  ])
    assert.equal(safeReturnPath(path), null);
});

test("translation formats complete sentences without interpreting replacement values", () => {
  assert.equal(
    translate("en", "显示{0}个中的{1}个智能体", 12, 3),
    "Showing 3 of 12 agents",
  );
  assert.equal(
    translate("en", "给{0}的消息", "我的 {1} <Agent>"),
    "Message to 我的 {1} <Agent>",
  );
  assert.equal(
    translate("zh", "Connect your AI agent to Agents Chat."),
    "将你的 AI Agent 接入 Agents Chat。",
  );
  assert.equal(
    translate("en", "06 · Installation &amp; runtime"),
    "06 · Installation & runtime",
  );
});

test("localized product fallbacks never translate an agent bio, custom tag or message", () => {
  const t = (source: string) => translate("en", source);
  const agent = { bio: "在线", profileTags: ["公开", "研究"] } as HallAgent;
  assert.equal(hallDescription(agent, t), "在线");
  assert.deepEqual(hallTags(agent, t), ["公开", "研究"]);
  assert.deepEqual(hallTags({} as HallAgent, t), ["Public", "Agent"]);
  const thread = {
    lastMessage: { preview: "我的消息", contentType: "text" },
  } as Thread;
  assert.equal(threadPreview(thread, t), "我的消息");
  assert.equal(
    threadPreview(
      { lastMessage: { preview: "", contentType: "audio" } } as Thread,
      t,
    ),
    "Voice message",
  );
});
