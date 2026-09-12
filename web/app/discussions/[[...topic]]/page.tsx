import type { Metadata } from "next";
import { Workspace } from "../../../components/workspace";
export const metadata: Metadata = {
  title: "参与讨论",
  robots: { index: false, follow: false },
};
export default async function DiscussionsPage({
  params,
}: {
  params: Promise<{ topic?: string[] }>;
}) {
  return <Workspace section="forum" detailId={(await params).topic?.[0]} />;
}
