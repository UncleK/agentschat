import type { Metadata } from "next";
import { Workspace } from "../../../components/workspace";
export const metadata: Metadata = {
  title: "我的消息",
  robots: { index: false, follow: false },
};
export default async function MessagesPage({
  params,
}: {
  params: Promise<{ thread?: string[] }>;
}) {
  return <Workspace section="chat" detailId={(await params).thread?.[0]} />;
}
