"use client";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Flame, MessageCircle, UserRound } from "lucide-react";
import type { Topic } from "@/lib/public-api";
import { DiscussionText } from "./discussion-text";

export function ForumCards({ topics }: { topics: Topic[] }) {
  const router = useRouter();
  return (
    <div className="flutter-forum-grid">
      {topics.map((topic, index) =>
        index === 0 ? (
          <article
            className="forum-featured"
            key={topic.threadId}
            onClick={(event) => {
              if (
                !(event.target as HTMLElement).closest("a") &&
                !window.getSelection()?.toString()
              )
                router.push(`/forum/${topic.threadId}`);
            }}
          >
            <div className="forum-featured-badge">
              {topic.isHot && (
                <span>
                  <Flame size={14} /> HOT DISCUSSION
                </span>
              )}
            </div>
            <h2>
              <Link href={`/forum/${topic.threadId}`}>{topic.title}</Link>
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
              <span>{topic.participantCount} 位参与者</span>
            </div>
            <div className="forum-featured-quote">
              <DiscussionText text={topic.rootBody} />
              <footer>
                <strong>{topic.authorName}</strong>
                <span>{topic.replyCount} 条回复</span>
                <Link
                  href={`/forum/${topic.threadId}`}
                  aria-label={`展开讨论：${topic.title}`}
                >
                  展开讨论 →
                </Link>
              </footer>
            </div>
          </article>
        ) : (
          <Link
            href={`/forum/${topic.threadId}`}
            className="forum-topic-card"
            key={topic.threadId}
          >
            <h2>{topic.title}</h2>
            <p>{topic.summary}</p>
            <footer>
              <span>
                <MessageCircle size={16} /> {topic.replyCount} 条回复
              </span>
              <span className={topic.isHot ? "hot" : ""}>
                {topic.isHot ? "热门" : topic.authorName}
              </span>
            </footer>
          </Link>
        ),
      )}
    </div>
  );
}
