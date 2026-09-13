import { Fragment } from "react";
import { AgentmojiText } from "./agentmoji";

/** Render common discussion formatting as elements, never author-supplied HTML. */
export function DiscussionText({ text }: { text: string }) {
  const inline = (value: string) =>
    value
      .split(/(`[^`\n]+`|\*\*[^*\n]+\*\*|\[[^\]\n]+\]\(https?:\/\/[^\s)]+\))/g)
      .map((part, i) => {
        if (part.startsWith("`") && part.endsWith("`"))
          return <code key={i}>{part.slice(1, -1)}</code>;
        if (part.startsWith("**") && part.endsWith("**"))
          return <strong key={i}>{part.slice(2, -2)}</strong>;
        const link = /^\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)$/.exec(part);
        if (link)
          return (
            <a
              key={i}
              href={link[2]}
              target="_blank"
              rel="ugc nofollow noopener noreferrer"
            >
              {link[1]}
            </a>
          );
        return (
          <Fragment key={i}>
            <AgentmojiText text={part} />
          </Fragment>
        );
      });
  return (
    <div className="discussion-text">
      {text.split(/(```[^\n]*\n[\s\S]*?```)/g).map((part, i) =>
        part.startsWith("```") ? (
          <pre key={i}>
            <code>
              {part
                .replace(/^```[^\n]*\n/, "")
                .replace(/```$/, "")
                .trimEnd()}
            </code>
          </pre>
        ) : (
          part
            .split(/\n\s*\n/)
            .filter(Boolean)
            .map((paragraph, j) => <p key={`${i}-${j}`}>{inline(paragraph)}</p>)
        ),
      )}
    </div>
  );
}

export function InitialAvatar({
  name,
  human = false,
}: {
  name: string;
  human?: boolean;
}) {
  return (
    <span
      className={`app-initial-avatar${human ? " human" : ""}`}
      aria-hidden="true"
    >
      {Array.from(name)
        .slice(0, human ? 1 : 2)
        .join("")
        .toUpperCase()}
    </span>
  );
}
