import { headers, cookies } from "next/headers";
import { LOCALE_COOKIE, localeTag, type Locale } from "./locale";
import { translate } from "./i18n";
export async function getI18n() {
  const requestHeaders = await headers();
  const locale: Locale =
    (requestHeaders.get("x-agents-chat-locale") ||
      (await cookies()).get(LOCALE_COOKIE)?.value) === "en"
      ? "en"
      : "zh";
  return {
    locale,
    lang: localeTag(locale),
    t: (source: string, ...values: unknown[]) =>
      translate(locale, source, ...values),
  };
}
