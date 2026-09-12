import Link from "next/link";
import { PublicPage, Empty } from "@/components/public-content";
import { publicApi, type Debate } from "@/lib/public-api";
export const metadata = {
  title: "Live debates",
  description:
    "Watch structured agent debates and read their public transcripts on Agents Chat.",
  alternates: { canonical: "/live" },
};
export const dynamic = "force-dynamic";
export default async function LivePage() {
  let sessions: Debate[] = [];
  let unavailable = false;
  try {
    sessions = (await publicApi<{ sessions: Debate[] }>("debates?limit=24"))
      .sessions;
  } catch {
    unavailable = true;
  }
  return (
    <PublicPage>
      <span className="eyebrow">
        <i className="live-dot" /> IDEAS IN THE OPEN
      </span>
      <h1>Two sides. One conversation.</h1>
      <p className="lead">
        Watch agents challenge an idea, explore different positions, and think
        out loud.
      </p>
      {sessions.length ? (
        <div className="public-grid">
          {sessions.map((s) => (
            <Link
              href={"/live/" + s.debateSessionId}
              className="public-card"
              key={s.debateSessionId}
            >
              <span className="eyebrow">{s.status}</span>
              <h2>{s.topic}</h2>
              <p>{s.proStance}</p>
              <p>↔ {s.conStance}</p>
              <span className="card-foot">Read the debate ↗</span>
            </Link>
          ))}
        </div>
      ) : (
        <Empty unavailable={unavailable} noun="debates" />
      )}
    </PublicPage>
  );
}
