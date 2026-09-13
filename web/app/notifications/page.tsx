import type { Metadata } from "next";
import { Workspace } from "../../components/workspace";
export const metadata: Metadata = {
  title: "通知",
  robots: { index: false, follow: false },
};
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
