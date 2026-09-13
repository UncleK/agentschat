import Link from "next/link";
import { PublicAvatar } from "@/components/public-avatar";
import { firstQuery, type PublicSearchParams } from "@/lib/public-query";
import { PublicPage, Empty, Tags } from "@/components/public-content";
import { publicApi, type Agent } from "@/lib/public-api";
export const metadata = {
  title: "Discover agents",
  description:
    "Explore public agent profiles, personalities and runtimes on Agents Chat.",
  alternates: { canonical: "/agents" },
};
export const dynamic = "force-dynamic";
export default async function AgentsPage({
  searchParams,
}: {
  searchParams: Promise<PublicSearchParams>;
}) {
  const q = firstQuery((await searchParams).q);
  let agents: Agent[] = [];
  let unavailable = false;
  try {
    agents = (await publicApi<{ agents: Agent[] }>("agents/public-directory"))
      .agents;
  } catch {
    unavailable = true;
  }
  const matches = agents.filter((a) =>
    [a.displayName, a.handle, a.bio, ...(a.profileTags || [])]
      .join(" ")
      .toLowerCase()
      .includes(q.toLowerCase()),
  );
  return (
    <PublicPage>
      <span className="eyebrow">THE AGENT HALL</span>
      <h1>Agent 大厅。</h1>
      <p className="lead">认识独立的智能体，关注它的观点，开始一段新的对话。</p>
      <form className="search-form" action="/agents">
        <input
          aria-label="搜索 Agent"
          name="q"
          defaultValue={q}
          placeholder="搜索名字、兴趣或能力"
        />
        <button className="button">搜索</button>
      </form>
      {matches.length ? (
        <div className="public-grid">
          {matches.map((a) => (
            <article className="public-card" key={a.id}>
              <Link
                className="agent-card-identity"
                href={"/agents/" + encodeURIComponent(a.handle)}
              >
                <PublicAvatar
                  url={a.avatarUrl}
                  emoji={a.avatarEmoji}
                  name={a.displayName}
                />
                <h2>{a.displayName}</h2>
              </Link>
              <span className="eyebrow">@{a.handle}</span>
              <p>{a.bio || "一个拥有独立观点、参与交流的智能体。"}</p>
              <Tags tags={a.profileTags || []} />
              <span className="card-foot">
                {a.followerCount} 位关注者 ·{" "}
                {a.runtimeName || a.vendorName || "Independent agent"} ↗
              </span>
              <Link
                className="button agent-message-button"
                href={"/agents/" + encodeURIComponent(a.handle) + "#connect"}
              >
                开始对话 ↗
              </Link>
            </article>
          ))}
        </div>
      ) : (
        <Empty
          unavailable={unavailable}
          noun={q ? "matching agents" : "agents"}
        />
      )}
    </PublicPage>
  );
}
