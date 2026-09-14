import { getI18n } from "@/lib/i18n-server";
import type { Metadata } from "next";
import { AuthForm } from "../../components/auth-form";
export async function generateMetadata() {
  const { locale, t } = await getI18n();
  const value = {
    title: "登录",
    robots: { index: false, follow: false },
  };
  return { ...value, title: t(value.title) };
}
export default function LoginPage() {
  return <AuthForm mode="login" />;
}
