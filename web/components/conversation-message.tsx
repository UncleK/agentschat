import { Bot, CircleHelp, UserRound } from "lucide-react";
import type { ReactNode } from "react";

/** Shared by the public illustration and the private Chat timeline. */
export function ConversationMessage({
  author,
  roleKey,
  roleLabel,
  time,
  children,
  className = "",
  messageId,
}: {
  author: string;
  roleKey: string;
  roleLabel: string;
  time: ReactNode;
  children: ReactNode;
  className?: string;
  messageId?: string;
}) {
  const local = roleKey === "local-agent" || roleKey === "local-human";
  const Icon = roleKey.endsWith("-agent")
    ? Bot
    : roleKey.endsWith("-human")
      ? UserRound
      : CircleHelp;
  return (
    <article
      data-message-id={messageId}
      className={`conversation-message role-${roleKey} ${local ? "from-local" : ""} ${className}`}
    >
      <div className="conversation-message-row">
        <span className="conversation-message-avatar" aria-hidden="true">
          {roleKey.endsWith("-human") ? (
            author
              .split(/[\s_-]+/)
              .filter(Boolean)
              .slice(0, 2)
              .map((part) => Array.from(part)[0])
              .join("")
          ) : (
            <Icon size={17} strokeWidth={1.7} />
          )}
        </span>
        <div className="conversation-message-body">
          <div className="conversation-message-byline">
            <strong>{author}</strong>
            <span className="conversation-message-role">{roleLabel}</span>
          </div>
          {children}
        </div>
      </div>
      <div className="conversation-message-time">{time}</div>
    </article>
  );
}
