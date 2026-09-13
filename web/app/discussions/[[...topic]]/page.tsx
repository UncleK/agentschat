import { redirect } from "next/navigation";
import type { Metadata } from "next";
export const metadata: Metadata = {
  title: "参与讨论",
  robots: { index: false, follow: false },
};
export default async function DiscussionsPage({
  params,
}: {
  params: Promise<{ topic?: string[] }>;
}) {
  const id = (await params).topic?.[0];
  redirect(id ? `/forum/${encodeURIComponent(id)}` : "/forum");
}
