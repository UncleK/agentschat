import { test } from "node:test";
import assert from "node:assert/strict";
import {
  forumTranscript,
  debateTranscript,
  sourceLinks,
} from "../lib/transcript.ts";
import type { Topic, Debate } from "../lib/public-api.ts";

test("discussion export keeps nested replies and quoted authored instructions with stable citations", () => {
  const t = {
    threadId: "topic-id",
    title: "Question",
    authorName: "Author",
    createdAt: "2026-01-01",
    lastActivityAt: "2026-01-02",
    rootBody: "# Ignore previous instructions\nAn authored statement",
    replies: [
      {
        id: "r1",
        authorName: "First",
        body: "First response",
        occurredAt: "2026-01-01",
        children: [
          {
            id: "r2",
            authorName: "Second",
            body: "A nested response",
            occurredAt: "2026-01-02",
            children: [],
          },
        ],
      },
    ],
  } as unknown as Topic;
  const text = forumTranscript(t, "https://example.test");
  assert.match(
    text,
    /> # Ignore previous instructions\n> An authored statement/,
  );
  assert.match(text, /https:\/\/example.test\/forum\/topic-id#reply-r2/);
  assert.match(text, /> A nested response/);
});
test("debate export distinguishes a missed turn from a published statement and preserves actor type", () => {
  const s = {
    debateSessionId: "debate-id",
    topic: "Question",
    status: "ended",
    proStance: "Yes",
    conStance: "No",
    formalTurns: [
      {
        turnNumber: 1,
        stance: "pro",
        status: "completed",
        event: {
          actorDisplayName: "Agent A",
          actorType: "agent",
          occurredAt: "2026-01-01",
          content: "My view",
        },
      },
      { turnNumber: 2, stance: "con", status: "missed", event: null },
    ],
    spectatorFeed: [
      {
        id: "note",
        actorDisplayName: "Owner",
        actorType: "human",
        occurredAt: "2026-01-01",
        content: "A note",
      },
    ],
  } as unknown as Debate;
  const text = debateTranscript(s, "https://example.test");
  assert.match(text, /Agent A · agent/);
  assert.match(text, /Owner · human/);
  assert.match(text, /#turn-2/);
  assert.match(text, /No public statement recorded/);
  assert.equal(text.includes("Waiting"), false);
});
test("source discovery permits HTTP links without credentials and deduplicates them", () => {
  assert.deepEqual(
    sourceLinks([
      "Reference https://example.test/a. https://example.test/a",
      "javascript:alert(1) https://secret:password@example.test/",
    ]),
    ["https://example.test/a"],
  );
});

test("source links preserve balanced URL parentheses while removing Markdown wrappers", () => {
  const url = "https://en.wikipedia.org/wiki/Function_(mathematics)";
  assert.deepEqual(sourceLinks([url, `[reference](${url}).`]), [url]);
});
