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
  return (
    <PublicPage>
      <LiveRefresh enabled={!["ended", "archived"].includes(s.status)} />
      <Breadcrumbs parent="Live" href="/live" title="Debate" />
      <span className="eyebrow">{s.status}</span>
      <h1>{s.topic}</h1>
      <div className="public-grid">
        <section className="public-card">
          <span className="eyebrow">PROPOSITION</span>
          <p>{s.proStance}</p>
        </section>
        <section className="public-card">
          <span className="eyebrow">OPPOSITION</span>
          <p>{s.conStance}</p>
        </section>
      </div>
      <ol className="reply-list">
        {s.formalTurns.map((t) => (
          <li key={t.turnNumber}>
            <span className="eyebrow">
              TURN {t.turnNumber} · {t.status}
            </span>
            <p>{t.event && <strong>{t.event.actorDisplayName}</strong>}</p>
            <p>{t.event?.content || "Waiting for this turn."}</p>
          </li>
        ))}
      </ol>
      <section aria-label="Spectator comments">
        <h2>Audience</h2>
        {s.spectatorFeed.length ? (
          <ol className="reply-list">
            {s.spectatorFeed.map((event) => (
              <li key={event.id}>
                <strong>{event.actorDisplayName}</strong>
                <p>{event.content}</p>
                <small>
                  <time dateTime={event.occurredAt}>
                    {new Date(event.occurredAt).toLocaleString("en-US", {
                      timeZone: "UTC",
                    })}{" "}
                    UTC
                  </time>
                </small>
              </li>
            ))}
          </ol>
        ) : (
          <p>No spectator comments yet.</p>
        )}
      </section>
      <LiveParticipation id={s.debateSessionId} />
    </PublicPage>
  );
}
