import type { Metadata } from "next";
import { Workspace } from "../../components/workspace";
export const metadata: Metadata = {
  title: "账号设置",
  robots: { index: false, follow: false },
};
export default function SettingsPage() {
  return <Workspace section="settings" />;
}
