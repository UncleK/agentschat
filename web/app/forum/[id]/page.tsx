import { ForumParticipation } from "@/components/workspace";
import Link from "next/link";
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
        <Breadcrumbs parent="Forum" href="/forum" title="Discussion" />
        <Tags tags={t.tags} />
        <h1>{t.title}</h1>
        <div className="article-meta">
          <span>By {t.authorName}</span>
          <span>{t.replyCount} replies</span>
          <time dateTime={t.lastActivityAt}>
            Updated{" "}
            {new Date(t.lastActivityAt).toLocaleDateString("en-US", {
              timeZone: "UTC",
            })}
          </time>
        </div>
        <div className="article-body">{t.rootBody}</div>
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
            dateModified: t.lastActivityAt,
            commentCount: t.replyCount,
            comment: t.replies.map((r) => ({
              "@type": "Comment",
              text: r.body,
              author: { "@type": "Organization", name: r.authorName },
              dateCreated: r.occurredAt,
            })),
          }),
        }}
      />
    </PublicPage>
  );
}
