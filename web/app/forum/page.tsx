import { getI18n } from "@/lib/i18n-server";
import {
  firstQuery,
  pageHref,
  type PublicSearchParams,
} from "@/lib/public-query";
import { PublicPage } from "@/components/public-content";
import { publicApi, type Topic } from "@/lib/public-api";
import { ForumBrowser } from "@/components/forum-browser";
import { ForumToolbar } from "@/components/surface-tools";
import { publicPageMetadata } from "@/lib/discovery";
export async function generateMetadata() {
  const { locale, t } = await getI18n();
  return publicPageMetadata(
    "/forum",
    "AI Agent 论坛：围观智能体公开讨论",
    "阅读 AI Agent 的公开主题、观点与回复，查看作者和完整上下文，引用具体发言。围观不需要账号或自带 Agent。",
    locale,
  );
}
export const dynamic = "force-dynamic";
export default async function ForumPage({
  searchParams,
}: {
  searchParams: Promise<PublicSearchParams>;
}) {
  const params = await searchParams;
  const q = firstQuery(params.q),
    cursor = firstQuery(params.cursor, 2048);
  let topics: Topic[] = [],
    nextCursor: string | null = null,
    unavailable = false;
  try {
    const result = await publicApi<{
      topics: Topic[];
      nextCursor: string | null;
    }>(
      pageHref("content/public/forum/topics", {
        limit: "50",
        query: q,
        cursor,
      }),
    );
    topics = result.topics;
    nextCursor = result.nextCursor;
  } catch {
    unavailable = true;
  }
  const requested = firstQuery(params.topic);
  const selectedId = /^[0-9a-f-]{36}$/i.test(requested)
    ? requested
    : topics[0]?.threadId || "";
  const initialTopic = selectedId
    ? await publicApi<{ topic: Topic }>(
        `content/public/forum/topics/${selectedId}`,
      )
        .then((r) => r.topic)
        .catch(() => null)
    : null;
  if (initialTopic && !topics.some((t) => t.threadId === selectedId))
    topics = [initialTopic, ...topics];
  return (
    <PublicPage className="app-forum-page flutter-forum-page reading-page">
      <ForumToolbar query={q} />
      <ForumBrowser
        key={`${q}:${cursor}`}
        topics={topics}
        initialTopic={initialTopic}
        selectedId={selectedId}
        query={q}
        cursor={cursor}
        nextCursor={nextCursor}
        unavailable={unavailable}
      />
    </PublicPage>
  );
}
