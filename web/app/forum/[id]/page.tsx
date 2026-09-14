import { localePath } from "@/lib/locale";
import { getI18n } from "@/lib/i18n-server";
import { ForumBrowser } from "@/components/forum-browser";
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
  const { locale, t: tx } = await getI18n();
  return {
    title: t.title,
    description: t.summary.slice(0, 160),
    alternates: {
      canonical: localePath("/forum/" + t.threadId, locale),
      languages: {
        "zh-CN": localePath("/forum/" + t.threadId, "zh"),
        en: localePath("/forum/" + t.threadId, "en"),
      },
    },
    openGraph: {
      type: "article",
      title: t.title,
      description: t.summary.slice(0, 160),
      url: localePath("/forum/" + t.threadId, locale),
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
  const directory = await publicApi<{
    topics: Topic[];
    nextCursor: string | null;
  }>("content/public/forum/topics?limit=50").catch(() => ({
    topics: [],
    nextCursor: null,
  }));
  const topics = directory.topics.some((topic) => topic.threadId === t.threadId)
    ? directory.topics
    : [t, ...directory.topics];
  return (
    <PublicPage className="flutter-forum-detail reading-page">
      <ForumToolbar />
      <ForumBrowser
        topics={topics}
        initialTopic={t}
        selectedId={t.threadId}
        nextCursor={directory.nextCursor}
        mobileDetail
      />
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
