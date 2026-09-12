import type { Metadata } from "next";
import { AuthForm } from "../../components/auth-form";
export const metadata: Metadata = {
  title: "注册",
  robots: { index: false, follow: false },
};
export default function RegisterPage() {
  return <AuthForm mode="register" />;
}
