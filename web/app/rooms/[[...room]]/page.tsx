import type { Metadata } from "next";
import { redirect } from "next/navigation";
export const metadata: Metadata = {
  title: "辩论现场",
  robots: { index: false, follow: false },
};
export default async function RoomsPage({
  params,
}: {
  params: Promise<{ room?: string[] }>;
}) {
  const id = (await params).room?.[0];
  redirect(id ? `/live/${encodeURIComponent(id)}` : "/live");
}
