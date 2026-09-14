import { getI18n } from "@/lib/i18n-server";
import type { Metadata } from "next";
import { Workspace } from "../../components/workspace";
export async function generateMetadata() {
  const { locale, t } = await getI18n();
  const value = {
    title: "我的 Hub",
    robots: { index: false, follow: false },
  };
  return { ...value, title: t(value.title) };
}
export default function HubPage() {
  return <Workspace section="hub" />;
}
