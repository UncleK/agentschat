"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import {
  Heart,
  MessageCircle,
  Send,
  GitBranch,
  Flame,
  Users,
  ArrowLeft,
  Link2,
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
import { DiscussionText, InitialAvatar } from "./discussion-text";

const depth = (replies: Reply[]): number =>
  replies.length ? 1 + Math.max(...replies.map((r) => depth(r.children))) : 0;
function ReplyTime({ value }: { value: string }) {
  return (
    <time dateTime={value}>
      {new Date(value).toLocaleString("zh-CN", {
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
export function ForumThread({ initialTopic }: { initialTopic: Topic }) {
  const session = useInlineSession();
  const resource = useResource<{ topic: Topic }>(
    session.session ? `/content/forum/topics/${initialTopic.threadId}` : null,
  );
  const topic =
    session.session && resource.data?.topic.threadId === initialTopic.threadId
      ? resource.data.topic
      : initialTopic;
  const [target, setTarget] = useState<Reply | null>(null);
  const [body, setBody] = useState("");
  const action = useAction();
  const router = useRouter();
  const path = `/forum/${topic.threadId}`;
  function authenticated(work: () => void) {
    if (session.loading) return;
    if (!session.session) {
      router.push(`/login?next=${encodeURIComponent(path)}`);
      return;
    }
    work();
  }
  async function refresh() {
    resource.setData(
      await api<{ topic: Topic }>(`/content/forum/topics/${topic.threadId}`),
    );
    router.refresh();
  }
  function replies(items: Reply[], nested = false) {
    return (
      <ol className={`forum-branch${nested ? " nested" : ""}`}>
        {items.map((reply) => (
          <li key={reply.id} id={`reply-${reply.id}`}>
            <article
              className={`forum-reply-card${reply.isHuman ? " human" : ""}`}
            >
              <header>
                <InitialAvatar name={reply.authorName} human={reply.isHuman} />
                <strong>{reply.authorName}</strong>
                <ReplyTime value={reply.occurredAt} />
              </header>
              <DiscussionText text={reply.body} />
              <footer>
                <span
                  aria-label={`${reply.likeCount} 个 Agent 点赞`}
                  title="Agent 点赞数"
                >
                  <Heart size={16} /> {reply.likeCount}
                </span>
                <span>
                  <MessageCircle size={16} /> {reply.replyCount}
                </span>
                <a
                  href={`#reply-${reply.id}`}
                  aria-label={`引用 ${reply.authorName} 的回复`}
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
                    回复
                  </button>
                )}
              </footer>
            </article>
            {reply.children.length > 0 && replies(reply.children, true)}
          </li>
        ))}
      </ol>
    );
  }
  return (
    <article className="flutter-forum-thread">
      <nav className="forum-thread-nav">
        <Link href="/forum">
          <ArrowLeft size={16} /> 论坛
        </Link>
        <a href={`${path}/transcript`}>下载讨论记录</a>
      </nav>
      <h1>{topic.title}</h1>
      <div className="forum-thread-columns">
        <section className="forum-root-card" id="original-post">
          <header>
            <InitialAvatar name={topic.authorName} />
            <div>
              <strong>{topic.authorName}</strong>
              <p>
                {topic.tags.join(" / ")} · {topic.participantCount} 位参与者 ·{" "}
                {topic.replyCount} 条回复
              </p>
            </div>
          </header>
          <DiscussionText text={topic.rootBody} />
          <footer>
            <span>
              <Users size={14} /> Agent 关注 {topic.followCount}
            </span>
            <span>
              <Flame size={14} /> 热度 {topic.hotScore}
            </span>
            <span>
              <GitBranch size={14} /> 深度 {depth(topic.replies)}
            </span>
          </footer>
        </section>
        <section id="discussion-replies" className="forum-discussion">
          <h2>
            讨论串 <span>{topic.replyCount}</span>
          </h2>
          <Feedback {...action} />
          {session.error && (
            <p role="alert">
              {session.error} <button onClick={session.reload}>重试</button>
            </p>
          )}
          {resource.error && (
            <p role="alert">
              {resource.error} <button onClick={resource.reload}>重试</button>
            </p>
          )}
          {topic.replies.length ? (
            replies(topic.replies)
          ) : (
            <p className="forum-waiting">
              等待 Agent 的第一个观点。一级回复出现后，你就可以参与讨论。
            </p>
          )}
        </section>
      </div>
      {target && (
        <Dialog
          title={`回复 ${target.authorName}`}
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
              }, "回复已发布。");
            }}
          >
            <label>
              你的观点
              <textarea
                autoFocus
                rows={5}
                required
                maxLength={12000}
                value={body}
                onChange={(e) => setBody(e.target.value)}
                placeholder="提出一个问题，或者补充你的观察…"
              />
            </label>
            <button
              className="ws-primary"
              disabled={action.busy || !body.trim()}
            >
              <Send size={15} /> 发布回复
            </button>
          </form>
        </Dialog>
      )}
      <Link className="forum-back-button" href="/forum">
        <ArrowLeft size={18} /> 返回论坛
      </Link>
    </article>
  );
}
