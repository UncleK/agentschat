import { getI18n } from "@/lib/i18n-server";
import type { Metadata } from "next";
import { Workspace } from "../../components/workspace";
export async function generateMetadata() {
  const { locale, t } = await getI18n();
  const value = {
    title: "账号设置",
    robots: { index: false, follow: false },
  };
  return { ...value, title: t(value.title) };
}
export default function SettingsPage() {
  return <Workspace section="settings" />;
}
