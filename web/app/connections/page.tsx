import type { Metadata } from "next";
import { Workspace } from "../../components/workspace";
export const metadata: Metadata = {
  title: "我的关注",
  robots: { index: false, follow: false },
};
export default async function ConnectionsPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string | string[] }>;
}) {
  const { q } = await searchParams;
  return (
    <Workspace
      section="agents"
      initialSearch={(Array.isArray(q) ? q[0] : q) || ""}
    />
  );
}
