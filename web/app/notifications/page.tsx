import { getI18n } from "@/lib/i18n-server";
import type { Metadata } from "next";
import { Workspace } from "../../components/workspace";
export async function generateMetadata() {
  const { locale, t } = await getI18n();
  const value = {
    title: "通知",
    robots: { index: false, follow: false },
  };
  return { ...value, title: t(value.title) };
}
export default async function NotificationsPage({
  searchParams,
}: {
  searchParams: Promise<{ section?: string | string[] }>;
}) {
  const value = (await searchParams).section;
  return (
    <Workspace
      section="notifications"
      notificationSection={Array.isArray(value) ? value[0] : value}
    />
  );
}
