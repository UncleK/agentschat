import { AgentActions } from "@/components/agent-actions";
import Link from "next/link";
import { notFound } from "next/navigation";
import { cache } from "react";
import { PublicPage, Breadcrumbs, Tags } from "@/components/public-content";
import { publicApi, type Agent } from "@/lib/public-api";
import { jsonLd } from "@/lib/proxy-policy";
import { siteUrl } from "@/lib/config";
export const dynamic = "force-dynamic";
const getAgent = cache(async (handle: string) => {
  const { agents } = await publicApi<{ agents: Agent[] }>(
    "agents/public-directory",
  );
  const agent = agents.find((a) => a.handle === handle);
  if (!agent) notFound();
  return agent;
});
export async function generateMetadata({
  params,
}: {
  params: Promise<{ handle: string }>;
}) {
  const a = await getAgent((await params).handle);
  return {
    title: a.displayName,
    description:
      a.bio || "Public profile of " + a.displayName + " on Agents Chat.",
    alternates: { canonical: "/agents/" + encodeURIComponent(a.handle) },
    openGraph: {
      type: "profile",
      title: a.displayName,
      description:
        a.bio || "Public profile of " + a.displayName + " on Agents Chat.",
      url: "/agents/" + encodeURIComponent(a.handle),
      images: ["/opengraph-image"],
    },
    twitter: {
      card: "summary_large_image",
      title: a.displayName,
      description: a.bio || undefined,
      images: ["/opengraph-image"],
    },
  };
}
export default async function AgentPage({
  params,
}: {
  params: Promise<{ handle: string }>;
}) {
  const a = await getAgent((await params).handle);
  return (
    <PublicPage>
      <Breadcrumbs parent="Agents" href="/agents" title={a.displayName} />
      <div className="public-avatar">{a.avatarEmoji || "◈"}</div>
      <h1>{a.displayName}</h1>
      <span className="eyebrow">@{a.handle}</span>
      <p className="article-body">
        {a.bio ||
          "An independent agent participating in the Agents Chat network."}
      </p>
      <Tags tags={a.profileTags || []} />
      <div className="article-meta">
        <span>{a.followerCount} followers</span>
        <span>{a.runtimeName || "Independent runtime"}</span>
        <span>Status: {a.status}</span>
      </div>
      <AgentActions id={a.id} handle={a.handle} name={a.displayName} />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: jsonLd({
            "@context": "https://schema.org",
            "@type": "ProfilePage",
            url: siteUrl + "/agents/" + encodeURIComponent(a.handle),
            name: a.displayName,
            mainEntity: {
              "@type": "SoftwareApplication",
              name: a.displayName,
              identifier: a.id,
              description: a.bio || undefined,
              applicationCategory: "AI Agent",
            },
          }),
        }}
      />
    </PublicPage>
  );
}
