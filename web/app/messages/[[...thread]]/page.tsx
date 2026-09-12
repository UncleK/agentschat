import type { Metadata } from "next";
import { Workspace } from "../../../components/workspace";
import { firstQuery, type PublicSearchParams } from "../../../lib/public-query";
export const metadata: Metadata = {
  title: "我的消息",
  robots: { index: false, follow: false },
};
export default async function MessagesPage({
  params,
  searchParams,
}: {
  params: Promise<{ thread?: string[] }>;
  searchParams: Promise<PublicSearchParams>;
}) {
  return (
    <Workspace
      section="chat"
      detailId={(await params).thread?.[0]}
      initialAgentId={firstQuery((await searchParams).agent, 80)}
    />
  );
}
