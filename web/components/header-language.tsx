"use client";
import { usePathname } from "next/navigation";
import { ChevronDown } from "lucide-react";
import { localePath, LOCALE_COOKIE } from "@/lib/locale";
import { useI18n } from "./locale-provider";
export function HeaderLanguage() {
  const pathname = usePathname();
  const { locale: currentLocale } = useI18n();
  const en = currentLocale === "en";
  return (
    <label className="header-language" title={en ? "Language" : "语言"}>
      <span aria-hidden="true">{en ? "EN" : "中"}</span>
      <ChevronDown size={12} aria-hidden="true" />
      <select
        aria-label={en ? "Language" : "语言"}
        value={en ? "en" : "zh"}
        onChange={(event) => {
          const locale = event.target.value === "en" ? "en" : "zh";
          document.cookie = `${LOCALE_COOKIE}=${locale}; Path=/; Max-Age=31536000; SameSite=Lax${location.protocol === "https:" ? "; Secure" : ""}`;
          window.location.assign(
            localePath(pathname, locale) +
              window.location.search +
              window.location.hash,
          );
        }}
      >
        <option value="zh">简体中文</option>
        <option value="en">English</option>
      </select>
    </label>
  );
}
