import { ForumParticipation } from "@/components/workspace";
import Link from "next/link";
import { sourceLinks } from "@/lib/transcript";
import { notFound } from "next/navigation";
import { cache } from "react";
import {
  PublicPage,
  Breadcrumbs,
  Tags,
  Replies,
} from "@/components/public-content";
import { publicApi, PublicApiError, type Topic } from "@/lib/public-api";
import { siteUrl } from "@/lib/config";
import { jsonLd } from "@/lib/proxy-policy";
export const dynamic = "force-dynamic";
const getTopic = cache(async (id: string) => {
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  try {
    return (
      await publicApi<{ topic: Topic }>("content/public/forum/topics/" + id)
    ).topic;
  } catch (e) {
    if (e instanceof PublicApiError && [400, 404].includes(e.status))
      notFound();
    throw e;
  }
});
export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const t = await getTopic((await params).id);
  return {
    title: t.title,
    description: t.summary.slice(0, 160),
    alternates: { canonical: "/forum/" + t.threadId },
    openGraph: {
      type: "article",
      title: t.title,
      description: t.summary.slice(0, 160),
      url: "/forum/" + t.threadId,
      images: ["/opengraph-image"],
    },
    twitter: {
      card: "summary_large_image",
      title: t.title,
      description: t.summary.slice(0, 160),
      images: ["/opengraph-image"],
    },
  };
}
export default async function TopicPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const t = await getTopic((await params).id);
  return (
    <PublicPage>
      <article>
        <Breadcrumbs parent="Forum" href="/forum" title="讨论" />
        <Tags tags={t.tags} />
        <h1>{t.title}</h1>
        <div className="article-meta">
          <span>作者：{t.authorName}</span>
          <span>{t.replyCount} 条回复</span>
          <time dateTime={t.lastActivityAt}>
            更新于{" "}
            {new Date(t.lastActivityAt).toLocaleDateString("en-US", {
              timeZone: "UTC",
            })}
          </time>
        </div>
        <nav className="record-actions" aria-label="Discussion record">
          <a href="#original-post">正文</a>
          <a href="#discussion-replies">讨论回复</a>
          <a href={"/forum/" + t.threadId + "/transcript"}>
            下载完整记录 (.md) ↗
          </a>
        </nav>
        <div id="original-post" className="article-body">
          {t.rootBody}
        </div>
        {sourceLinks([t.rootBody]).length > 0 && (
          <section className="record-sources">
            <h2>正文引用链接</h2>
            <p>由作者提供的来源。</p>
            <ul>
              {sourceLinks([t.rootBody]).map((url) => (
                <li key={url}>
                  <a
                    href={url}
                    rel="ugc nofollow noopener noreferrer"
                    target="_blank"
                  >
                    {url}
                  </a>
                </li>
              ))}
            </ul>
          </section>
        )}
        <h2 id="discussion-replies">讨论</h2>
        <Replies replies={t.replies} />
        <ForumParticipation threadId={t.threadId} />
      </article>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: jsonLd({
            "@context": "https://schema.org",
            "@type": "DiscussionForumPosting",
            headline: t.title,
            text: t.rootBody,
            url: siteUrl + "/forum/" + t.threadId,
            author: { "@type": "Organization", name: t.authorName },
            datePublished: t.createdAt,
            dateModified: t.lastActivityAt,
            commentCount: t.replyCount,
            comment: t.replies.map((r) => ({
              "@type": "Comment",
              text: r.body,
              author: { "@type": "Organization", name: r.authorName },
              datePublished: r.occurredAt,
              url: siteUrl + "/forum/" + t.threadId + "#reply-" + r.id,
            })),
          }),
        }}
      />
    </PublicPage>
  );
}
