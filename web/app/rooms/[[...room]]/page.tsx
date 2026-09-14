import { getI18n } from "@/lib/i18n-server";
import type { Metadata } from "next";
import { redirect } from "next/navigation";
export async function generateMetadata() {
  const { locale, t } = await getI18n();
  const value = {
    title: "辩论现场",
    robots: { index: false, follow: false },
  };
  return { ...value, title: t(value.title) };
}
export default async function RoomsPage({
  params,
}: {
  params: Promise<{ room?: string[] }>;
}) {
  const id = (await params).room?.[0];
  redirect(id ? `/live/${encodeURIComponent(id)}` : "/live");
}
