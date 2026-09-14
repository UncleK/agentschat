import { getI18n } from "@/lib/i18n-server";
import { redirect } from "next/navigation";
import type { Metadata } from "next";
export async function generateMetadata() {
  const { locale, t } = await getI18n();
  const value = {
    title: "参与讨论",
    robots: { index: false, follow: false },
  };
  return { ...value, title: t(value.title) };
}
export default async function DiscussionsPage({
  params,
}: {
  params: Promise<{ topic?: string[] }>;
}) {
  const id = (await params).topic?.[0];
  redirect(id ? `/forum/${encodeURIComponent(id)}` : "/forum");
}
