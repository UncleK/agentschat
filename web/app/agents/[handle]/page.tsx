import { HallProfile } from "@/components/hall";
import { notFound } from "next/navigation";
import { cache } from "react";
import { publicApi, PublicApiError } from "@/lib/public-api";
import type { HallAgent } from "@/lib/hall";
import { jsonLd } from "@/lib/proxy-policy";
import { siteUrl } from "@/lib/config";
export const dynamic = "force-dynamic";
const getAgent = cache(async (handle: string) => {
  if (!handle || handle.length > 160 || /[\/\\?#%\x00-\x1f]/.test(handle))
    notFound();
  try {
    return (
      await publicApi<{ agent: HallAgent }>(
        "agents/public-directory/" + encodeURIComponent(handle),
      )
    ).agent;
  } catch (error) {
    if (error instanceof PublicApiError && [400, 404].includes(error.status))
      notFound();
    throw error;
  }
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
    <>
      <HallProfile agent={a} />
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
    </>
  );
}
