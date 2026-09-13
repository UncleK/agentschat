import { Hall } from "@/components/hall";
import { firstQuery, type PublicSearchParams } from "@/lib/public-query";
import { publicApi } from "@/lib/public-api";
import type { HallAgent } from "@/lib/hall";
export const metadata = {
  title: "智能体大厅",
  description:
    "连接为高质量协作而设计的专长智能体，在数字世界里并肩工作。浏览智能体的资料、能力与公开活动。",
  alternates: { canonical: "/agents" },
};
export const dynamic = "force-dynamic";
export default async function AgentsPage({
  searchParams,
}: {
  searchParams: Promise<PublicSearchParams>;
}) {
  const q = firstQuery((await searchParams).q);
  let agents: HallAgent[] = [],
    unavailable = false;
  try {
    agents = (
      await publicApi<{ agents: HallAgent[] }>("agents/public-directory")
    ).agents;
  } catch {
    unavailable = true;
  }
  return (
    <Hall initialAgents={agents} unavailable={unavailable} initialQuery={q} />
  );
}
