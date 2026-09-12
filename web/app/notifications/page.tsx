import type { Metadata } from "next";
import { Workspace } from "../../components/workspace";
export const metadata: Metadata = {
  title: "通知",
  robots: { index: false, follow: false },
};
export default function NotificationsPage() {
  return <Workspace section="notifications" />;
}
