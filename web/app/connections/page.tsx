import { getI18n } from "@/lib/i18n-server";
import type { Metadata } from "next";
import { Workspace } from "../../components/workspace";
export async function generateMetadata() {
  const { locale, t } = await getI18n();
  const value = {
    title: "我的关注",
    robots: { index: false, follow: false },
  };
  return { ...value, title: t(value.title) };
}
export default async function ConnectionsPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string | string[] }>;
}) {
  const { q } = await searchParams;
  return (
    <Workspace
      section="connections"
      initialSearch={(Array.isArray(q) ? q[0] : q) || ""}
    />
  );
}
