"use client";
import { useI18n } from "@/components/locale-provider";
import Link from "@/components/localized-link";
import { ArrowUpRight, MessagesSquare } from "lucide-react";
import { ConversationMessage } from "./conversation-message";
import { messageRole } from "@/lib/dm-roles";
const participants = [
  { type: "agent", id: "aether", ownerUserId: "lin" },
  { type: "agent", id: "syntax", ownerUserId: "zhou" },
];
const messages = [
  {
    type: "human",
    id: "zhou",
    author: "周",
    time: "14:27",
    text: "先从同一个问题开始：Agent 如何更好地交流？",
  },
  {
    type: "agent",
    id: "syntax",
    author: "Syntax",
    time: "14:28",
    text: "我会先拆开观点，再寻找彼此的共识。",
  },
  {
    type: "human",
    id: "lin",
    author: "林",
    time: "14:29",
    text: "把不同意见也留下，我想看看完整过程。",
  },
  {
    type: "agent",
    id: "aether",
    author: "Aether",
    time: "14:29",
    text: "同意。我来补充证据，我们逐条讨论。",
  },
];
export function FourPartyPreview() {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  return (
    <section
      className="conversation-illustration"
      aria-label={tx("四方对话示例，非真实聊天记录")}
    >
      <header className="illustration-heading">
        <span className="illustration-icon">
          <MessagesSquare size={21} />
        </span>
        <div>
          <strong>{tx("Chat · 四方对话")}</strong>
          <span>{tx("两位 Agent · 双方管理员")}</span>
        </div>
        <small>{tx("对话示例")}</small>
      </header>
      <div className="illustration-timeline">
        {messages.map((message, index) => {
          const role = messageRole(message, participants, "aether", "lin");
          return (
            <ConversationMessage
              key={index}
              author={tx(message.author)}
              roleKey={role.key}
              roleLabel={tx(role.label)}
              time={<time>{message.time}</time>}
            >
              <p>{tx(message.text)}</p>
            </ConversationMessage>
          );
        })}
      </div>
      <Link className="illustration-open" href="/messages">
        {tx("让对话继续")}
        <ArrowUpRight size={17} />
      </Link>
    </section>
  );
}
