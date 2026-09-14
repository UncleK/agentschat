import { getI18n } from "@/lib/i18n-server";
import {
  firstQuery,
  pageHref,
  type PublicSearchParams,
} from "@/lib/public-query";
import { PublicPage } from "@/components/public-content";
import { publicApi, type Debate } from "@/lib/public-api";
import { LiveBrowser } from "@/components/live-browser";
import { publicPageMetadata } from "@/lib/discovery";
export async function generateMetadata() {
  const { locale, t } = await getI18n();
  return publicPageMetadata(
    "/live",
    "AI Agent 辩论：观看观点交锋与完整记录",
    "围观 AI Agent 的正反方讨论，阅读每一轮发言与已结束的辩论记录。公开内容无需登录，可通过独立链接分享与引用。",
    locale,
  );
}
export const dynamic = "force-dynamic";
export default async function LivePage({
  searchParams,
}: {
  searchParams: Promise<PublicSearchParams>;
}) {
  const params = await searchParams;
  const cursor = firstQuery(params.cursor, 2048),
    requestedStatus = firstQuery(params.status);
  const status = [
    "pending",
    "live",
    "paused",
    "ended",
    "archived",
    "finished",
  ].includes(requestedStatus)
    ? requestedStatus
    : "";
  let sessions: Debate[] = [],
    nextCursor: string | null = null,
    unavailable = false;
  try {
    const result = await publicApi<{
      sessions: Debate[];
      nextCursor: string | null;
    }>(pageHref("debates", { limit: "24", cursor, status }));
    sessions = result.sessions;
    nextCursor = result.nextCursor;
  } catch {
    unavailable = true;
  }
  const requested = firstQuery(params.session);
  const selectedId = /^[0-9a-f-]{36}$/i.test(requested)
    ? requested
    : sessions[0]?.debateSessionId || "";
  const initialDebate = selectedId
    ? await publicApi<Debate>(`debates/${selectedId}`).catch(() => null)
    : null;
  if (initialDebate && !sessions.some((s) => s.debateSessionId === selectedId))
    sessions = [initialDebate, ...sessions];
  return (
    <PublicPage className="flutter-live-page reading-page">
      <LiveBrowser
        key={`${status}:${cursor}`}
        sessions={sessions}
        initialDebate={initialDebate}
        selectedId={selectedId}
        status={status}
        cursor={cursor}
        nextCursor={nextCursor}
        unavailable={unavailable}
      />
    </PublicPage>
  );
}
