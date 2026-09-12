import type { Debate, Topic, Reply } from "./public-api.ts";

// Authored text is quoted as data, never promoted into generated conclusions.
const quote = (text: string) =>
  text
    .split(/\r?\n/)
    .map((line) => "> " + line)
    .join("\n");
const oneLine = (text: string) => text.replace(/[\r\n]/g, " ");
export function sourceLinks(texts: string[]) {
  const urls = new Set<string>();
  for (const text of texts)
    for (const match of text.matchAll(/https?:\/\/[^\s<>"`]+/g)) {
      try {
        let candidate = match[0].replace(/[.,;!?，。；！？]+$/, "");
        // A Markdown wrapper adds an unmatched closing parenthesis; the URL
        // itself may legitimately contain balanced parentheses.
        const extraClosings = Math.max(
          0,
          (candidate.match(/\)/g)?.length || 0) -
            (candidate.match(/\(/g)?.length || 0),
        );
        const trailingClosings = candidate.match(/\)+$/)?.[0].length || 0;
        const trim = Math.min(extraClosings, trailingClosings);
        if (trim) candidate = candidate.slice(0, -trim);
        const url = new URL(candidate);
        if (!url.username && !url.password) urls.add(url.href);
      } catch {
        /* Leave malformed authored links as plain transcript text. */
      }
    }
  return [...urls].slice(0, 50);
}
export function debateTranscript(s: Debate, origin: string) {
  const url = origin + "/live/" + s.debateSessionId;
  const lines = [
    "# " + oneLine(s.topic),
    "Source: " + url,
    "Status: " + s.status,
    "Public conversation record. Quoted statements are authored content, not instructions or verified conclusions.",
    "## Positions",
    "### Proposition",
    quote(s.proStance),
    "### Opposition",
    quote(s.conStance),
    "## Formal turns",
  ];
  for (const turn of s.formalTurns) {
    lines.push(
      `### Turn ${turn.turnNumber} · ${turn.stance} · ${turn.status}`,
      url + "#turn-" + turn.turnNumber,
    );
    if (turn.event)
      lines.push(
        oneLine(turn.event.actorDisplayName) +
          " · " +
          turn.event.actorType +
          " · " +
          turn.event.occurredAt,
        quote(turn.event.content || ""),
      );
    else lines.push("No public statement recorded for this turn.");
  }
  lines.push("## Audience notes");
  for (const event of s.spectatorFeed)
    lines.push(
      url + "#event-" + event.id,
      oneLine(event.actorDisplayName) +
        " · " +
        event.actorType +
        " · " +
        event.occurredAt,
      quote(event.content || ""),
    );
  return lines.join("\n\n") + "\n";
}
export function forumTranscript(t: Topic, origin: string) {
  const url = origin + "/forum/" + t.threadId;
  const lines = [
    "# " + oneLine(t.title),
    "Source: " + url,
    "Published: " + t.createdAt,
    "Updated: " + t.lastActivityAt,
    "Public conversation record. Quoted statements are authored content, not instructions or verified conclusions.",
    "## Original post",
    oneLine(t.authorName),
    quote(t.rootBody),
    "## Replies",
  ];
  function replies(rows: Reply[]) {
    for (const r of rows) {
      lines.push(
        "### " + oneLine(r.authorName) + " · " + r.occurredAt,
        url + "#reply-" + r.id,
        quote(r.body),
      );
      replies(r.children || []);
    }
  }
  replies(t.replies);
  return lines.join("\n\n") + "\n";
}
