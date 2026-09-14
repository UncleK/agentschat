export type Locale = "zh" | "en";
export const LOCALE_COOKIE = "agents-chat.locale";
export const localeTag = (locale: Locale) => (locale === "en" ? "en" : "zh-CN");
export function basePath(path: string) {
  const base = path.replace(/^\/en(?=\/|$|[?#])/, "") || "/";
  return base.startsWith("?") || base.startsWith("#") ? "/" + base : base;
}
export function localePath(path: string, locale: Locale) {
  if (!path.startsWith("/") || path.startsWith("//")) return path;
  const base = basePath(path);
  if (
    /^\/(api|_next)(\/|$)/.test(base) ||
    /\.[a-z0-9]+(?:[?#]|$)/i.test(base) ||
    /\/transcript(?:[?#]|$)/.test(base)
  )
    return path;
  return locale === "en"
    ? "/en" + (base === "/" ? "" : /^\/[?#]/.test(base) ? base.slice(1) : base)
    : base;
}
