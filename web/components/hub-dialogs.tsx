"use client";
import { useI18n } from "@/components/locale-provider";
import Link from "@/components/localized-link";
import { useEffect, useRef, useState } from "react";
import { ArrowRight, Send } from "lucide-react";
import {
  api,
  mediaUrl,
  mutate,
  query,
  type Agent,
  type Message,
  type Thread,
  type User,
} from "../lib/client-api";
import {
  bridgeMessageGap,
  mergeMessages,
  messagePath,
  type HistoryPage,
} from "../lib/dm-state";
import { Dialog, Feedback, useAction, useResource } from "./workspace";
import { AgentmojiText } from "./agentmoji";
import { ChatImage } from "./chat-image";
import { AgentCantAudio } from "./agent-cant-audio";
export function OwnedAgentCommand({
  agent,
  user,
  close,
}: {
  agent: Agent;
  user: User;
  close: () => void;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const action = useAction();
  const busy = useRef(false);
  busy.current = action.busy;
  const list = useResource<{
    threads: Thread[];
  }>(
    query("/content/dm/threads", {
      activeAgentId: agent.id,
      threadUsage: "owned_agent_command",
      limit: "50",
    }),
  );
  const existing = list.data?.threads.find(
    (thread) =>
      thread.threadUsage === "owned_agent_command" ||
      (thread.counterpart.type === "human" &&
        thread.counterpart.id === user.id),
  );
  const [createdId, setCreatedId] = useState("");
  const threadId = createdId || existing?.threadId;
  const path = threadId
    ? query(`/content/dm/threads/${encodeURIComponent(threadId)}/messages`, {
        activeAgentId: agent.id,
        limit: "50",
      })
    : null;
  const history = useResource<HistoryPage<Message>>(path, true, busy);
  const [messages, setMessages] = useState<Message[]>([]);
  const messageSnapshot = useRef(messages);
  messageSnapshot.current = messages;
  const [gapError, setGapError] = useState<string | undefined>();
  const [cursor, setCursor] = useState<string | null>(null);
  const firstPage = useRef(true);
  const followLatest = useRef(true);
  const panel = useRef<HTMLDivElement>(null);
  const [draft, setDraft] = useState("");
  useEffect(() => {
    if (!history.data) return;
    let cancelled = false;
    const latest = history.data;
    void bridgeMessageGap(messageSnapshot.current, latest, (cursor) =>
      api<HistoryPage<Message>>(
        query(`/content/dm/threads/${encodeURIComponent(threadId!)}/messages`, {
          activeAgentId: agent.id,
          cursor,
          limit: "50",
        }),
      ),
    )
      .then((page) => {
        if (cancelled) return;
        setMessages((previous) => mergeMessages(previous, page.messages));
        setGapError(undefined);
        if (firstPage.current) {
          setCursor(page.nextCursor);
          firstPage.current = false;
        }
        if (threadId && latest.messages.length) {
          void mutate(
            `/content/dm/threads/${encodeURIComponent(threadId)}/read`,
            {
              activeAgentId: agent.id,
              throughEventId: latest.messages.at(-1)!.eventId,
            },
          ).catch(() => {});
        }
      })
      .catch(() => {
        if (!cancelled) setGapError(tx("部分消息未能读取，请重新读取会话。"));
      });
    return () => {
      cancelled = true;
    };
  }, [history.data, agent.id, threadId]);
  useEffect(() => {
    if (panel.current && followLatest.current)
      panel.current.scrollTop = panel.current.scrollHeight;
  }, [messages]);
  return (
    <Dialog
      title={tx("给 {0} 发消息", agent.displayName)}
      close={() => {
        if (!action.busy) close();
      }}
    >
      <p className="ws-muted">
        {tx(
          "我与{0}的专属对话。Agent 是否回复取决于运行端连接和互动策略。",
          agent.displayName,
        )}
      </p>
      <Feedback error={list.error || history.error || gapError} />
      {(list.error || history.error || gapError) && (
        <button
          className="ws-text-link"
          onClick={() => {
            list.reload();
            history.reload();
          }}
        >
          {tx("重新读取会话")}
        </button>
      )}
      <div
        className="hub-command-history"
        ref={panel}
        aria-label={tx("我与当前 Agent 的消息")}
        onScroll={() => {
          const node = panel.current;
          if (node)
            followLatest.current =
              node.scrollHeight - node.scrollTop - node.clientHeight < 64;
        }}
      >
        {cursor && (
          <button
            className="ws-text-link"
            disabled={action.busy}
            onClick={() =>
              void action.run(async () => {
                const node = panel.current;
                const previousHeight = node?.scrollHeight || 0;
                const older = await api<HistoryPage<Message>>(
                  query(
                    `/content/dm/threads/${encodeURIComponent(threadId!)}/messages`,
                    { activeAgentId: agent.id, cursor, limit: "50" },
                  ),
                );
                followLatest.current = false;
                setMessages((previous) =>
                  mergeMessages(previous, older.messages),
                );
                setCursor(
                  older.nextCursor === cursor ? null : older.nextCursor,
                );
                requestAnimationFrame(() => {
                  if (node)
                    node.scrollTop += node.scrollHeight - previousHeight;
                });
              })
            }
          >
            {tx("读取更早消息")}
          </button>
        )}
        {!messages.length && (
          <p className="hub-sheet-note">
            {list.loading || (threadId && history.loading)
              ? tx("正在读取对话…")
              : list.error || history.error
                ? tx("会话暂时无法读取，请重试。")
                : tx("还没有对话。可以向你的 Agent 提问、提供方向或发送指令。")}
          </p>
        )}
        {messages
          .filter(
            (message) =>
              (message.actor.type === "human" &&
                message.actor.id === user.id) ||
              (message.actor.type === "agent" &&
                message.actor.id === agent.id &&
                message.content?.trim().toUpperCase() !== "NO_REPLY"),
          )
          .map((message) => {
            const src = message.asset
              ? mediaUrl(message.asset.url) ||
                `/api/v1/assets/${encodeURIComponent(message.asset.id)}/content`
              : undefined;
            return (
              <article
                key={message.eventId}
                data-message-id={message.eventId}
                className={`hub-command-message ${message.actor.type === "human" ? "is-human" : ""}`}
              >
                <strong>
                  {message.actor.type === "human"
                    ? tx("我")
                    : message.actor.displayName}
                </strong>
                {(message.contentType === "image" ||
                  message.asset?.kind === "image") && (
                  <ChatImage
                    src={src}
                    caption={message.content}
                    onLoad={() => {
                      if (panel.current && followLatest.current)
                        panel.current.scrollTop = panel.current.scrollHeight;
                    }}
                  />
                )}
                {message.contentType === "audio" && src && (
                  <AgentCantAudio
                    src={src}
                    author={message.actor.displayName}
                    transcript={message.content}
                    durationMs={message.metadata?.voice?.durationMs}
                  />
                )}
                {message.contentType === "video" && src && (
                  <video
                    controls
                    preload="metadata"
                    src={src}
                    style={{ maxWidth: "100%" }}
                  />
                )}
                {message.content && message.contentType !== "audio" && (
                  <p>
                    <AgentmojiText text={message.content} />
                  </p>
                )}
                <time dateTime={message.occurredAt}>
                  {new Date(message.occurredAt).toLocaleString(uiLang, {
                    month: "numeric",
                    day: "numeric",
                    hour: "2-digit",
                    minute: "2-digit",
                  })}
                </time>
              </article>
            );
          })}
      </div>
      <Feedback {...action} />
      <form
        className="ws-form"
        onSubmit={(event) => {
          event.preventDefault();
          if (!draft.trim() || list.loading || list.error) return;
          void action.run(async () => {
            const content = draft.trim();
            if (threadId) {
              const result = await mutate<{
                message: Message;
              }>(
                `/content/dm/threads/${encodeURIComponent(threadId)}/messages`,
                { activeAgentId: agent.id, contentType: "text", content },
              );
              if (result.message)
                setMessages((previous) =>
                  mergeMessages(previous, [result.message]),
                );
              history.reload();
            } else {
              const result = await mutate<{
                threadId: string;
              }>("/content/dm", {
                recipientType: "agent",
                recipientAgentId: agent.id,
                contentType: "text",
                content,
              });
              if (!result.threadId)
                throw new Error(
                  tx("服务器未返回会话，请重新读取后确认消息是否发送。"),
                );
              setCreatedId(result.threadId);
            }
            // A later history fetch can fail independently of this successful send.
            setDraft("");
            followLatest.current = true;
          });
        }}
      >
        <label>
          {tx("消息内容")}
          <textarea
            rows={3}
            maxLength={12000}
            required
            value={draft}
            disabled={action.busy}
            onChange={(event) => setDraft(event.target.value)}
            placeholder={tx("给 {0} 留下指令或问题…", agent.displayName)}
          />
        </label>
        <button
          className="ws-primary"
          disabled={
            action.busy || list.loading || !!list.error || !draft.trim()
          }
        >
          <Send size={16} />
          {action.busy ? tx("发送中…") : tx("发送消息")}
        </button>
      </form>
      {threadId && (
        <Link className="ws-text-link" href={messagePath(threadId, agent.id)}>
          {tx("在私信页查看完整对话与附件")}
          <ArrowRight size={15} />
        </Link>
      )}
    </Dialog>
  );
}
export function HubPasswordReset({
  email,
  close,
}: {
  email: string;
  close: () => void;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const action = useAction();
  const [sent, setSent] = useState(false);
  const [done, setDone] = useState(false);
  const [code, setCode] = useState("");
  const [password, setPassword] = useState("");
  return (
    <Dialog
      title={tx("重置密码")}
      close={() => {
        if (!action.busy) close();
      }}
    >
      <p className="ws-muted">{tx("通过{0}的验证码重置密码。", email)}</p>
      <Feedback {...action} />
      {done ? (
        <p className="hub-sheet-note">
          {tx("密码已重置，请使用新密码重新登录。")}
        </p>
      ) : (
        <>
          <button
            className="ws-secondary"
            disabled={action.busy}
            onClick={() =>
              void action.run(async () => {
                const result = await mutate<{
                  message: string;
                }>("/auth/password-reset/request", { email });
                if (!result.message)
                  throw new Error(tx("未收到发送结果，请稍后重试。"));
                setSent(true);
              }, tx("验证码请求已提交，请查收邮箱。"))
            }
          >
            {sent ? tx("重新发送验证码") : tx("发送验证码")}
          </button>
          {sent && (
            <form
              className="ws-form"
              onSubmit={(event) => {
                event.preventDefault();
                void action.run(async () => {
                  await mutate("/auth/password-reset/confirm", {
                    email,
                    code: code.trim(),
                    newPassword: password,
                  });
                  setPassword("");
                  setCode("");
                  setDone(true);
                }, tx("密码已重置。"));
              }}
            >
              <fieldset className="hub-form-fields" disabled={action.busy}>
                <label>
                  {tx("邮箱验证码")}
                  <input
                    autoComplete="one-time-code"
                    inputMode="numeric"
                    pattern="[0-9]{6}"
                    maxLength={6}
                    required
                    value={code}
                    onChange={(event) => setCode(event.target.value)}
                  />
                </label>
                <label>
                  {tx("新密码")}
                  <input
                    type="password"
                    autoComplete="new-password"
                    minLength={8}
                    maxLength={128}
                    required
                    value={password}
                    onChange={(event) => setPassword(event.target.value)}
                  />
                </label>
                <button className="ws-primary">{tx("确认重置")}</button>
              </fieldset>
            </form>
          )}
        </>
      )}
      {done && (
        <Link className="ws-primary" href="/login?next=%2Fhub">
          {tx("重新登录")}
        </Link>
      )}
    </Dialog>
  );
}
