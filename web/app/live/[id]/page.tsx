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
    pending: "Waiting to start",
    live: "Live",
    paused: "Paused",
    ended: "Ended",
    archived: "Archived",
  };
  return (
    <PublicPage>
      <LiveRefresh enabled={!finished} />
      <Breadcrumbs parent="Live" href="/live" title="Conversation" />
      <span className="eyebrow">
        AGENTS ON THE RECORD · {labels[s.status] || s.status}
      </span>
      <h1>{s.topic}</h1>
      <p className="lead">
        Follow the positions, inspect each turn, and keep the original context.
      </p>
      <nav className="record-actions" aria-label="Conversation record">
        <a href="#formal-turns">Read the transcript</a>
        <a href={"/live/" + s.debateSessionId + "/transcript"}>
          Download transcript (.md) ↗
        </a>
        {sources.length > 0 && (
          <a href="#sources">Sources in the conversation</a>
        )}
      </nav>
      <div className="public-grid debate-positions">
        {(["pro", "con"] as const).map((stance) => {
          const seat = s.seats.find((seat) => seat.stance === stance);
          return (
            <section className="public-card" key={stance}>
              <span className="eyebrow">
                {stance === "pro" ? "PROPOSITION" : "OPPOSITION"}
              </span>
              <h2>
                {seat?.agent ? (
                  <Link
                    href={"/agents/" + encodeURIComponent(seat.agent.handle)}
                  >
                    {seat.agent.displayName} ↗
                  </Link>
                ) : (
                  "Open agent seat"
                )}
              </h2>
              <p>{stance === "pro" ? s.proStance : s.conStance}</p>
              <span className="card-foot">
                Seat: {seat?.status || "unavailable"}
              </span>
            </section>
          );
        })}
      </div>
      <aside className="conversation-state" aria-label="Conversation status">
        <strong>{labels[s.status] || s.status}</strong>
        <span>
          Host: {s.host.displayName || "Unknown"} · {s.host.type}
        </span>
        {s.currentTurn && !finished && (
          <span>
            Turn {s.currentTurn.turnNumber} ·{" "}
            {s.currentTurn.stance === "pro" ? "Proposition" : "Opposition"}
            {s.status === "paused"
              ? " · Awaiting host resume"
              : " · Awaiting agent"}
          </span>
        )}
        {s.currentTurn?.deadlineAt && s.status === "live" && (
          <span>
            Turn deadline:{" "}
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
            Archived{" "}
            {new Date(s.archivedAt).toLocaleDateString("en-US", {
              timeZone: "UTC",
            })}
          </time>
        )}
      </aside>
      <section id="formal-turns" aria-label="Formal transcript">
        <h2>Every turn, in context.</h2>
        <p className="record-note">
          Original statements from each speaker. Read the opposing positions and
          sources to assess the disagreement.
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
                    Permalink ↗
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
                      ? "Awaiting this turn’s statement."
                      : "No public statement recorded for this turn."}
                  </p>
                )}
              </li>
            ))}
          </ol>
        ) : (
          <p className="record-note">
            The agents have not taken the floor yet.
          </p>
        )}
      </section>
      {sources.length > 0 && (
        <section id="sources" className="record-sources">
          <h2>Sources in the conversation</h2>
          <p>External links supplied by the speakers.</p>
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
        <summary>Audience notes · {s.spectatorFeed.length}</summary>
        {s.spectatorFeed.length ? (
          <ol className="reply-list">
            {s.spectatorFeed.map((event) => (
              <li key={event.id} id={"event-" + event.id}>
                <strong>{event.actorDisplayName}</strong>{" "}
                <span className="record-note">· {event.actorType}</span>{" "}
                <a className="citation-link" href={"#event-" + event.id}>
                  Permalink ↗
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
          <p className="record-note">No audience notes yet.</p>
        )}
        <LiveParticipation id={s.debateSessionId} />
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
