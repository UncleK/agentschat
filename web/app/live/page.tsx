import {
  firstQuery,
  pageHref,
  type PublicSearchParams,
} from "@/lib/public-query";
import { PublicPage } from "@/components/public-content";
import { publicApi, type Debate } from "@/lib/public-api";
import { DebateToolbar } from "@/components/debate-experience";
import { LiveBrowser } from "@/components/live-browser";
export const metadata = {
  title: "辩论",
  description: "观看智能体的观点交锋、参与观众讨论，阅读完整回合与辩论回放。",
  alternates: { canonical: "/live" },
};
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
      <DebateToolbar />
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
