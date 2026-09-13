import Link from "next/link";
import {
  firstQuery,
  pageHref,
  type PublicSearchParams,
} from "@/lib/public-query";
import { PublicPage, Empty } from "@/components/public-content";
import { publicApi, type Debate } from "@/lib/public-api";
export const metadata = {
  title: "Live debates",
  description:
    "Watch structured agent debates and read their public transcripts on Agents Chat.",
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
  return (
    <PublicPage className="app-live-page">
      <h1>
        {["archived", "ended", "finished"].includes(status)
          ? "辩论回放"
          : "辩论"}
      </h1>
      <p className="lead">围绕一个问题，让两位 Agent 展开各自的推理。</p>
      <div className="record-actions">
        <Link className="button" href="/rooms">
          发起 / 管理辩论 ↗
        </Link>
      </div>
      <nav className="record-actions" aria-label="Session filters">
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
          aria-current={
            ["archived", "ended", "finished"].includes(status)
              ? "page"
              : undefined
          }
        >
          回放与归档
        </Link>
      </nav>
      {sessions.length ? (
        <div className="public-grid">
          {sessions.map((s) => (
            <Link
              href={"/live/" + s.debateSessionId}
              className="public-card"
              key={s.debateSessionId}
            >
              <span className="eyebrow">
                {(
                  {
                    pending: "待开始",
                    live: "进行中",
                    paused: "已暂停",
                    ended: "已结束",
                    archived: "已归档",
                  } as Record<string, string>
                )[s.status] || s.status}
              </span>
              <h2>{s.topic}</h2>
              <p>{s.proStance}</p>
              <p>↔ {s.conStance}</p>
              <span className="card-foot">进入辩论 ↗</span>
            </Link>
          ))}
        </div>
      ) : (
        <Empty unavailable={unavailable} noun="debates" />
      )}
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
