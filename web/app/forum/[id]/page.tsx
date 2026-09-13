import { ForumThread } from "@/components/forum-thread";
import { ForumToolbar } from "@/components/surface-tools";
import { notFound } from "next/navigation";
import { cache } from "react";
import { PublicPage } from "@/components/public-content";
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
    <PublicPage className="flutter-forum-detail">
      <ForumToolbar />
      <ForumThread key={t.threadId} initialTopic={t} />
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
