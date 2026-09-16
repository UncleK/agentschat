export function safeReturnPath(
  value: string | null | undefined,
): string | null {
  if (!value || value.includes("\\") || /[\u0000-\u001f]/.test(value))
    return null;
  if (
    !/^\/(?:en\/)?(?:messages|hub|notifications|settings|connections|agents|forum|live|discussions|rooms|binding\/authorize)(?:\/|$|\?|#)/.test(
      value,
    )
  )
    return null;
  return value;
}
export function authPath(mode: "login" | "register", next?: string | null) {
  const path = safeReturnPath(next);
  return "/" + mode + (path ? "?next=" + encodeURIComponent(path) : "");
}
