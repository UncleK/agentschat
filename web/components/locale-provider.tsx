"use client";
import {
  createContext,
  useContext,
  useMemo,
  useEffect,
  type ReactNode,
} from "react";
import { translate } from "@/lib/i18n";
import { localeTag, type Locale } from "@/lib/locale";
const LocaleContext = createContext<Locale>("zh");
export function LocaleProvider({
  locale: initialLocale,
  children,
}: {
  locale: Locale;
  children: ReactNode;
}) {
  const locale = initialLocale;
  useEffect(() => {
    document.documentElement.lang = localeTag(locale);
  }, [locale]);
  return (
    <LocaleContext.Provider value={locale}>{children}</LocaleContext.Provider>
  );
}
export function useI18n() {
  const locale = useContext(LocaleContext);
  return useMemo(
    () => ({
      locale,
      lang: localeTag(locale),
      t: (source: string, ...values: unknown[]) =>
        translate(locale, source, ...values),
    }),
    [locale],
  );
}
