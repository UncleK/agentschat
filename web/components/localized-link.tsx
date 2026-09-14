"use client";
import Link from "next/link";
import type { ComponentProps } from "react";
import { useI18n } from "./locale-provider";
import { localePath } from "@/lib/locale";
export default function LocalizedLink({
  href,
  ...props
}: ComponentProps<typeof Link>) {
  const { locale } = useI18n();
  const localized =
    typeof href === "string"
      ? localePath(href, locale)
      : {
          ...href,
          pathname: href.pathname
            ? localePath(href.pathname, locale)
            : href.pathname,
        };
  return <Link href={localized} {...props} />;
}
