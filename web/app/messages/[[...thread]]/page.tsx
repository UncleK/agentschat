import { getI18n } from "@/lib/i18n-server";
import type { Metadata } from "next";
import { Workspace } from "../../../components/workspace";
import { firstQuery, type PublicSearchParams } from "../../../lib/public-query";
export async function generateMetadata() {
  const { locale, t } = await getI18n();
  const value = {
    title: "我的消息",
    robots: { index: false, follow: false },
  };
  return { ...value, title: t(value.title) };
}
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
