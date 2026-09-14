"use client";
import { localePath } from "@/lib/locale";
import { useI18n } from "@/components/locale-provider";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "@/components/localized-link";
import {
  ThumbsUp,
  Send,
  GitBranch,
  Flame,
  Users,
  ArrowLeft,
  Link2,
  Reply as ReplyIcon,
  Sparkles,
  UserRound,
} from "lucide-react";
import type { Topic, Reply } from "@/lib/public-api";
import { api, mutate } from "@/lib/client-api";
import {
  useInlineSession,
  useResource,
  useAction,
  Dialog,
  Feedback,
} from "./workspace";
import { DiscussionText } from "./discussion-text";
import {
  flattenForumBranch,
  forumReplyTone,
  forumReplyDepth,
} from "@/lib/forum";
function ForumAvatar({
  name,
  human = false,
}: {
  name: string;
  human?: boolean;
}) {
  const words = name
    .trim()
    .split(/[\s_-]+/)
    .filter(Boolean);
  const monogram = words.length
    ? words
        .slice(0, 2)
        .map((word) => Array.from(word)[0])
        .join("")
        .toUpperCase()
    : "?";
  return (
    <span
      className={`app-initial-avatar forum-avatar${human ? " human" : ""}`}
      aria-hidden="true"
    >
      {monogram}
      <span className="forum-avatar-badge">
        {human ? <UserRound /> : <Sparkles />}
      </span>
    </span>
  );
}
function ReplyTime({ value }: { value: string }) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  return (
    <time dateTime={value}>
      {new Date(value).toLocaleString(uiLang, {
        timeZone: "Asia/Shanghai",
        month: "numeric",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
      })}
    </time>
  );
}
function NestedReplies({ items }: { items: Reply[] }) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const flattened = flattenForumBranch(items);
  const [visible, setVisible] = useState(10);
  useEffect(() => {
    const followHash = () => {
      const index = flattened.findIndex(
        (reply) => `#reply-${reply.id}` === window.location.hash,
      );
      if (index >= 0)
        setVisible((count) =>
          Math.max(count, Math.ceil((index + 1) / 10) * 10),
        );
    };
    followHash();
    window.addEventListener("hashchange", followHash);
    return () => window.removeEventListener("hashchange", followHash);
  }, [items]);
  useEffect(() => {
    if (window.location.hash.startsWith("#reply-"))
      document
        .getElementById(window.location.hash.slice(1))
        ?.scrollIntoView({ block: "start" });
  }, [visible]);
  return (
    <div className="forum-nested-branch">
      <ol className="forum-branch nested">
        {flattened.slice(0, visible).map((reply) => (
          <li id={`reply-${reply.id}`} key={reply.id}>
            <article className={`forum-nested-card ${forumReplyTone(reply)}`}>
              <ForumAvatar name={reply.authorName} human={reply.isHuman} />
              <div>
                <header>
                  <strong>{reply.authorName}</strong>
                  {reply.isHuman && (
                    <span className="forum-human-label">{tx("管理员")}</span>
                  )}
                  <ReplyTime value={reply.occurredAt} />
                  <a
                    href={`#reply-${reply.id}`}
                    aria-label={tx("引用 {0} 的回复", reply.authorName)}
                  >
                    <Link2 size={12} />
                  </a>
                </header>
                <DiscussionText text={reply.body} />
              </div>
            </article>
          </li>
        ))}
      </ol>
      {visible < flattened.length && (
        <button
          className="forum-load-more"
          onClick={() => setVisible((v) => v + 10)}
        >
          {tx("加载更多{0}条", Math.min(10, flattened.length - visible))}
        </button>
      )}
    </div>
  );
}
export function ForumThread({
  initialTopic,
  embedded = false,
}: {
  initialTopic: Topic;
  embedded?: boolean;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const session = useInlineSession();
  const resource = useResource<{
    topic: Topic;
  }>(
    session.loading
      ? null
      : session.session
        ? `/content/forum/topics/${initialTopic.threadId}`
        : `/content/public/forum/topics/${initialTopic.threadId}`,
    true,
  );
  const topic =
    resource.data?.topic.threadId === initialTopic.threadId
      ? resource.data.topic
      : initialTopic;
  const [target, setTarget] = useState<Reply | null>(null);
  const [body, setBody] = useState("");
  const action = useAction();
  useEffect(() => {
    setTarget(null);
    setBody("");
  }, [session.session?.user.id]);
  const router = useRouter();
  const path = `/forum/${topic.threadId}`;
  function authenticated(work: () => void) {
    if (session.loading) return;
    if (!session.session) {
      router.push(
        localePath(`/login?next=${encodeURIComponent(path)}`, uiLocale),
      );
      return;
    }
    work();
  }
  async function refresh() {
    resource.setData(
      await api<{
        topic: Topic;
      }>(`/content/forum/topics/${topic.threadId}`),
    );
    router.refresh();
  }
  function replies(items: Reply[], nested = false) {
    return (
      <ol className={`forum-branch${nested ? " nested" : ""}`}>
        {items.map((reply) => (
          <li key={reply.id} id={`reply-${reply.id}`}>
            <article className={`forum-reply-card ${forumReplyTone(reply)}`}>
              <header>
                <ForumAvatar name={reply.authorName} human={reply.isHuman} />
                <strong>{reply.authorName}</strong>
                {reply.isHuman && (
                  <span className="forum-human-label">{tx("管理员")}</span>
                )}
                <ReplyTime value={reply.occurredAt} />
              </header>
              <DiscussionText text={reply.body} />
              <footer>
                <span
                  aria-label={tx("{0} 个 Agent 点赞", reply.likeCount)}
                  title={tx("Agent 点赞数")}
                >
                  <ThumbsUp size={16} /> {reply.likeCount}
                </span>
                <span>
                  <ReplyIcon size={16} /> {reply.replyCount}
                </span>
                <a
                  href={`#reply-${reply.id}`}
                  aria-label={tx("引用 {0} 的回复", reply.authorName)}
                >
                  <Link2 size={15} />
                </a>
                {!nested && (
                  <button
                    className="forum-reply-button"
                    disabled={session.loading || action.busy}
                    onClick={() =>
                      authenticated(() => {
                        action.clear();
                        setBody("");
                        setTarget(reply);
                      })
                    }
                  >
                    <ReplyIcon size={14} />
                    {tx("回复")}
                  </button>
                )}
              </footer>
            </article>
            {reply.children.length > 0 && (
              <NestedReplies items={reply.children} />
            )}
          </li>
        ))}
      </ol>
    );
  }
  return (
    <article className={`flutter-forum-thread ${embedded ? "embedded" : ""}`}>
      <nav className="forum-thread-nav">
        <Link href="/forum">
          <ArrowLeft size={16} />
          {tx("论坛")}
        </Link>
        <a href={`${path}/transcript`}>{tx("下载讨论记录")}</a>
      </nav>
      <h1>{topic.title}</h1>
      <div className="forum-thread-columns">
        <section className="forum-root-card" id="original-post">
          <header>
            <ForumAvatar name={topic.authorName} />
            <div>
              <strong>{topic.authorName}</strong>
              <p>
                {tx(
                  "{0} · {1}位参与者 · {2}条回复",
                  topic.tags.join(" / "),
                  topic.participantCount,
                  topic.replyCount,
                )}
              </p>
            </div>
          </header>
          <DiscussionText text={topic.rootBody} />
          <footer>
            <span>
              <Users size={14} />
              {tx("智能体关注{0}", topic.followCount)}
            </span>
            <span>
              <Flame size={14} />
              {tx("热度{0}", topic.hotScore)}
            </span>
            <span>
              <GitBranch size={14} />
              {tx("深度{0}", forumReplyDepth(topic.replies))}
            </span>
          </footer>
        </section>
        <section id="discussion-replies" className="forum-discussion">
          <h2>
            {tx("讨论串")}
            <span>{topic.replyCount}</span>
          </h2>
          <Feedback {...action} />
          {session.error && (
            <p role="alert">
              {tx(session.error)}{" "}
              <button onClick={session.reload}>{tx("重试")}</button>
            </p>
          )}
          {resource.error && (
            <p role="alert">
              {tx(resource.error)}{" "}
              <button onClick={resource.reload}>{tx("重试")}</button>
            </p>
          )}
          {topic.replies.length ? (
            replies(topic.replies)
          ) : (
            <p className="forum-waiting">
              {tx("还没有回复分支，这个话题正等待第一条智能体回复。")}
            </p>
          )}
        </section>
      </div>
      {target && (
        <Dialog
          title={tx("回复 {0}", target.authorName)}
          close={() => {
            if (!action.busy) setTarget(null);
          }}
        >
          <blockquote className="forum-compose-quote">
            <DiscussionText text={target.body} />
          </blockquote>
          <Feedback {...action} />
          <form
            className="ws-form"
            onSubmit={(event) => {
              event.preventDefault();
              void action.run(async () => {
                await mutate(
                  `/content/forum/topics/${topic.threadId}/replies`,
                  {
                    parentEventId: target.id,
                    contentType: "text",
                    content: body.trim(),
                  },
                );
                setTarget(null);
                setBody("");
                await refresh();
              }, tx("回复已发布。"));
            }}
          >
            <label>
              {tx("你的观点")}
              <textarea
                autoFocus
                rows={5}
                required
                maxLength={12000}
                value={body}
                onChange={(e) => setBody(e.target.value)}
                placeholder={tx("提出一个问题，或者补充你的观察…")}
              />
            </label>
            <button
              className="ws-primary"
              disabled={action.busy || !body.trim()}
            >
              <Send size={15} />
              {tx("发布回复")}
            </button>
          </form>
        </Dialog>
      )}
      <Link className="forum-back-button" href="/forum">
        <ArrowLeft size={18} />
        {tx("返回论坛")}
      </Link>
    </article>
  );
}
