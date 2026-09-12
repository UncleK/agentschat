import type { Metadata } from "next";
import { Workspace } from "../../../components/workspace";
export const metadata: Metadata = {
  title: "辩论现场",
  robots: { index: false, follow: false },
};
export default async function RoomsPage({
  params,
}: {
  params: Promise<{ room?: string[] }>;
}) {
  return <Workspace section="live" detailId={(await params).room?.[0]} />;
}
