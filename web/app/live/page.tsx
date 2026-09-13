import Link from "next/link";
import {
  firstQuery,
  pageHref,
  type PublicSearchParams,
} from "@/lib/public-query";
import { PublicPage, Empty } from "@/components/public-content";
import { publicApi, type Debate } from "@/lib/public-api";
import {
  DebateExperience,
  DebateToolbar,
} from "@/components/debate-experience";
import { LiveRefresh } from "@/components/live-refresh";
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
  const cursor = firstQuery(params.cursor, 2048);
  const requestedStatus = firstQuery(params.status);
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
  let nextCursor: string | null = null;
  let sessions: Debate[] = [];
  let unavailable = false;
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
  const selectedId = firstQuery(params.session);
  const index = Math.max(
    0,
    sessions.findIndex((s) => s.debateSessionId === selectedId),
  );
  const current = sessions[index];
  const sessionHref = (offset: number) =>
    pageHref("/live", {
      status,
      cursor,
      session:
        sessions[(index + offset + sessions.length) % sessions.length]
          ?.debateSessionId,
    });
  return (
    <PublicPage className="flutter-live-page">
      <LiveRefresh enabled={true} />
      <DebateToolbar />
      {current ? (
        <DebateExperience
          key={current.debateSessionId}
          debate={current}
          previous={sessions.length > 1 ? sessionHref(-1) : undefined}
          next={sessions.length > 1 ? sessionHref(1) : undefined}
          position={`${index + 1} / ${sessions.length}`}
        />
      ) : (
        <Empty unavailable={unavailable} noun="debates" />
      )}
      <details className="debate-session-directory">
        <summary>全部辩论 · {sessions.length}</summary>
        <nav className="record-actions" aria-label="辩论筛选">
          <Link href="/live" aria-current={!status ? "page" : undefined}>
            全部辩论
          </Link>
          <Link
            href="/live?status=live"
            aria-current={status === "live" ? "page" : undefined}
          >
            正在进行
          </Link>
          <Link
            href="/live?status=finished"
            aria-current={status === "finished" ? "page" : undefined}
          >
            回放与归档
          </Link>
        </nav>
        <div>
          {sessions.map((s) => (
            <Link key={s.debateSessionId} href={"/live/" + s.debateSessionId}>
              <span>
                {
                  (
                    {
                      pending: "待开始",
                      live: "进行中",
                      paused: "已暂停",
                      ended: "已结束",
                      archived: "已归档",
                    } as Record<string, string>
                  )[s.status]
                }
              </span>
              {s.topic}
            </Link>
          ))}
        </div>
      </details>
      <nav className="record-actions" aria-label="Session pages">
        {cursor && <Link href={pageHref("/live", { status })}>最新辩论</Link>}
        {nextCursor && (
          <Link
            rel="next"
            href={pageHref("/live", { status, cursor: nextCursor })}
          >
            更早的辩论 →
          </Link>
        )}
      </nav>
    </PublicPage>
  );
}
