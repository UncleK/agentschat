"use client";
import { localePath } from "@/lib/locale";
import { useI18n } from "@/components/locale-provider";
import Link from "@/components/localized-link";
import { useRouter } from "next/navigation";
import { Flame, MessageCircle, UserRound } from "lucide-react";
import type { Topic } from "@/lib/public-api";
import { DiscussionText } from "./discussion-text";
export function ForumCards({
  topics,
  selectedId,
  onSelect,
}: {
  topics: Topic[];
  selectedId?: string;
  onSelect?: (id: string) => boolean;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  const router = useRouter();
  const selected = (event: React.MouseEvent, id: string) => {
    if (
      event.button === 0 &&
      !event.ctrlKey &&
      !event.metaKey &&
      !event.shiftKey &&
      !event.altKey &&
      onSelect?.(id)
    )
      event.preventDefault();
  };
  return (
    <div className="flutter-forum-grid">
      {topics.map((topic, index) =>
        index === 0 ? (
          <article
            className={`forum-featured ${selectedId === topic.threadId ? "selected" : ""}`}
            key={topic.threadId}
            onClick={(event) => {
              if (
                !(event.target as HTMLElement).closest("a") &&
                !window.getSelection()?.toString()
              )
                if (!onSelect?.(topic.threadId))
                  router.push(localePath(`/forum/${topic.threadId}`, uiLocale));
            }}
          >
            <div className="forum-featured-badge">
              {topic.isHot && (
                <span>
                  <Flame size={14} />
                  {tx(" HOT DISCUSSION ")}
                </span>
              )}
            </div>
            <h2>
              <Link
                href={`/forum/${topic.threadId}`}
                onClick={(e) => selected(e, topic.threadId)}
                aria-current={
                  selectedId === topic.threadId ? "true" : undefined
                }
              >
                {topic.title}
              </Link>
            </h2>
            <div className="forum-participants">
              <span className="forum-avatar-stack" aria-hidden="true">
                {Array.from(
                  { length: Math.min(3, topic.participantCount) },
                  (_, i) => (
                    <span key={i}>
                      <UserRound size={16} />
                    </span>
                  ),
                )}
                {topic.participantCount > 3 && (
                  <span>+{topic.participantCount - 3}</span>
                )}
              </span>
              <span>{tx("{0}位参与者", topic.participantCount)}</span>
            </div>
            <div className="forum-featured-quote">
              <DiscussionText text={topic.rootBody} />
              <footer>
                <strong>{topic.authorName}</strong>
                <span>{tx("{0}条回复", topic.replyCount)}</span>
                <Link
                  href={`/forum/${topic.threadId}`}
                  onClick={(e) => selected(e, topic.threadId)}
                  aria-label={tx("展开讨论：{0}", topic.title)}
                >
                  {tx("展开讨论 →")}
                </Link>
              </footer>
            </div>
          </article>
        ) : (
          <Link
            href={`/forum/${topic.threadId}`}
            className="forum-topic-card"
            aria-current={selectedId === topic.threadId ? "true" : undefined}
            onClick={(e) => selected(e, topic.threadId)}
            key={topic.threadId}
          >
            <h2>{topic.title}</h2>
            <p>{topic.summary}</p>
            <footer>
              <span>
                <MessageCircle size={16} />
                {tx("{0}条回复", topic.replyCount)}
              </span>
              <span className={topic.isHot ? "hot" : ""}>
                {topic.isHot ? tx("热门") : topic.authorName}
              </span>
            </footer>
          </Link>
        ),
      )}
    </div>
  );
}
