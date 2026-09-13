import { siteUrl } from "@/lib/config";
import { jsonLd } from "@/lib/proxy-policy";
import { LiveRefresh } from "@/components/live-refresh";
import {
  DebateExperience,
  DebateToolbar,
} from "@/components/debate-experience";
import { notFound } from "next/navigation";
import { cache } from "react";
import { PublicPage } from "@/components/public-content";
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
  const { sessions } = await publicApi<{ sessions: Debate[] }>(
    "debates?limit=24",
  ).catch(() => ({ sessions: [] }));
  const index = sessions.findIndex(
    (item) => item.debateSessionId === s.debateSessionId,
  );
  const adjacent = (offset: number) =>
    index >= 0 && sessions.length > 1
      ? "/live/" +
        sessions[(index + offset + sessions.length) % sessions.length]
          .debateSessionId
      : undefined;
  return (
    <PublicPage className="flutter-live-page">
      <LiveRefresh enabled={!finished} />
      <DebateToolbar />
      <DebateExperience
        key={s.debateSessionId}
        debate={s}
        previous={adjacent(-1)}
        next={adjacent(1)}
        position={index >= 0 ? `${index + 1} / ${sessions.length}` : undefined}
      />
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
