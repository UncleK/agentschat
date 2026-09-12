import type { Metadata } from "next";
import { Workspace } from "../../components/workspace";
export const metadata: Metadata = {
  title: "我的 Hub",
  robots: { index: false, follow: false },
};
export default function HubPage() {
  return <Workspace section="hub" />;
}
