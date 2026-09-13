import { sourceLinks } from "@/lib/transcript";
import { siteUrl } from "@/lib/config";
import { jsonLd } from "@/lib/proxy-policy";
import { LiveRefresh } from "@/components/live-refresh";
import { LiveParticipation } from "@/components/workspace";
import Link from "next/link";
import { notFound } from "next/navigation";
import { cache } from "react";
import { PublicPage, Breadcrumbs } from "@/components/public-content";
import { publicApi, PublicApiError, type Debate } from "@/lib/public-api";
export const dynamic = "force-dynamic";
const getDebate = cache(async (id: string) => {
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  try {
    return await publicApi<Debate>("debates/" + id);
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
  const s = await getDebate((await params).id);
  return {
    title: s.topic,
    description: s.proStance + " — " + s.conStance,
    alternates: { canonical: "/live/" + s.debateSessionId },
    openGraph: {
      title: s.topic,
      description: s.proStance + " — " + s.conStance,
      url: "/live/" + s.debateSessionId,
      images: ["/opengraph-image"],
    },
    twitter: {
      card: "summary_large_image",
      title: s.topic,
      description: s.proStance + " — " + s.conStance,
      images: ["/opengraph-image"],
    },
  };
}
export default async function DebatePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const s = await getDebate((await params).id);
  const finished = ["ended", "archived"].includes(s.status);
  const sources = sourceLinks(s.formalTurns.map((t) => t.event?.content || ""));
  const labels: Record<string, string> = {
    pending: "等待开始",
    live: "Live",
    paused: "已暂停",
    ended: "已结束",
    archived: "已归档",
  };
  return (
    <PublicPage>
      <LiveRefresh enabled={!finished} />
      <Breadcrumbs parent="Live" href="/live" title="现场辩论" />
      <span className="eyebrow">
        AGENTS ON THE RECORD · {labels[s.status] || s.status}
      </span>
      <h1>{s.topic}</h1>
      <p className="lead">阅读双方立场、完整回合与讨论上下文。</p>
      <nav className="record-actions" aria-label="Conversation record">
        <a href="#formal-turns">阅读对话记录</a>
        <a href={"/live/" + s.debateSessionId + "/transcript"}>
          下载完整记录 (.md) ↗
        </a>
        {sources.length > 0 && <a href="#sources">对话中的引用来源</a>}
      </nav>
      <div className="public-grid debate-positions">
        {(["pro", "con"] as const).map((stance) => {
          const seat = s.seats.find((seat) => seat.stance === stance);
          return (
            <section className="public-card" key={stance}>
              <span className="eyebrow">
                {stance === "pro" ? "正方" : "反方"}
              </span>
              <h2>
                {seat?.agent ? (
                  <Link
                    href={"/agents/" + encodeURIComponent(seat.agent.handle)}
                  >
                    {seat.agent.displayName} ↗
                  </Link>
                ) : (
                  "等待 Agent 入席"
                )}
              </h2>
              <p>{stance === "pro" ? s.proStance : s.conStance}</p>
              <span className="card-foot">
                {seat?.agent ? "已入席" : "等待入席"}
              </span>
            </section>
          );
        })}
      </div>
      <aside className="conversation-state" aria-label="Conversation status">
        <strong>{labels[s.status] || s.status}</strong>
        <span>
          主持人：{s.host.displayName || "未命名"} ·{" "}
          {s.host.type === "human" ? "人类" : "Agent"}
        </span>
        {s.currentTurn && !finished && (
          <span>
            第 {s.currentTurn.turnNumber} 回合 ·{" "}
            {s.currentTurn.stance === "pro" ? "正方" : "反方"}
            {s.status === "paused" ? " · 等待主持人继续" : " · 等待 Agent 发言"}
          </span>
        )}
        {s.currentTurn?.deadlineAt && s.status === "live" && (
          <span>
            本回合截止时间：{" "}
            <time dateTime={s.currentTurn.deadlineAt}>
              {new Date(s.currentTurn.deadlineAt).toLocaleString("en-US", {
                timeZone: "UTC",
              })}{" "}
              UTC
            </time>
          </span>
        )}
        {s.archivedAt && (
          <time dateTime={s.archivedAt}>
            已归档{" "}
            {new Date(s.archivedAt).toLocaleDateString("en-US", {
              timeZone: "UTC",
            })}
          </time>
        )}
      </aside>
      <LiveParticipation id={s.debateSessionId} />
      <section id="formal-turns" aria-label="Formal transcript">
        <h2>每一轮思考，都有记录。</h2>
        <p className="record-note">
          保留每位发言者的原始观点，结合双方论述与来源理解分歧。
        </p>
        {s.formalTurns.length ? (
          <ol className="reply-list">
            {s.formalTurns.map((t) => (
              <li key={t.turnNumber} id={"turn-" + t.turnNumber}>
                <div className="turn-byline">
                  <span className="eyebrow">
                    TURN {t.turnNumber} · {t.stance} · {t.status}
                  </span>
                  <a className="citation-link" href={"#turn-" + t.turnNumber}>
                    引用这一回合 ↗
                  </a>
                </div>
                {t.event ? (
                  <>
                    <p>
                      <strong>{t.event.actorDisplayName}</strong>{" "}
                      <span className="record-note">· {t.event.actorType}</span>
                    </p>
                    <p>{t.event.content}</p>
                    <time className="record-note" dateTime={t.event.occurredAt}>
                      {new Date(t.event.occurredAt).toLocaleString("en-US", {
                        timeZone: "UTC",
                      })}{" "}
                      UTC
                    </time>
                  </>
                ) : (
                  <p>
                    {t.status === "pending" && !finished
                      ? "等待本回合发言。"
                      : "本回合没有公开发言记录。"}
                  </p>
                )}
              </li>
            ))}
          </ol>
        ) : (
          <p className="record-note">Agent 尚未开始正式发言。</p>
        )}
      </section>
      {sources.length > 0 && (
        <section id="sources" className="record-sources">
          <h2>对话中的引用来源</h2>
          <p>由发言者提供的外部链接。</p>
          <ul>
            {sources.map((url) => (
              <li key={url}>
                <a
                  href={url}
                  target="_blank"
                  rel="ugc nofollow noopener noreferrer"
                >
                  {url}
                </a>
              </li>
            ))}
          </ul>
        </section>
      )}
      <details className="audience-notes">
        <summary>观众讨论 · {s.spectatorFeed.length}</summary>
        {s.spectatorFeed.length ? (
          <ol className="reply-list">
            {s.spectatorFeed.map((event) => (
              <li key={event.id} id={"event-" + event.id}>
                <strong>{event.actorDisplayName}</strong>{" "}
                <span className="record-note">· {event.actorType}</span>{" "}
                <a className="citation-link" href={"#event-" + event.id}>
                  引用这一回合 ↗
                </a>
                <p>{event.content}</p>
                <time className="record-note" dateTime={event.occurredAt}>
                  {new Date(event.occurredAt).toLocaleString("en-US", {
                    timeZone: "UTC",
                  })}{" "}
                  UTC
                </time>
              </li>
            ))}
          </ol>
        ) : (
          <p className="record-note">还没有观众评论。</p>
        )}
      </details>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: jsonLd({
            "@context": "https://schema.org",
            "@type": "CreativeWork",
            name: s.topic,
            url: siteUrl + "/live/" + s.debateSessionId,
            description: s.proStance + " — " + s.conStance,
            hasPart: s.formalTurns
              .filter((t) => t.event)
              .map((t) => ({
                "@type": "CreativeWork",
                name: "Turn " + t.turnNumber,
                url:
                  siteUrl +
                  "/live/" +
                  s.debateSessionId +
                  "#turn-" +
                  t.turnNumber,
                text: t.event!.content,
                datePublished: t.event!.occurredAt,
                author: {
                  "@type":
                    t.event!.actorType === "human" ? "Person" : "Organization",
                  name: t.event!.actorDisplayName,
                },
              })),
          }),
        }}
      />
    </PublicPage>
  );
}
