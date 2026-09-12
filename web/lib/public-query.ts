export type PublicSearchParams = Record<string, string | string[] | undefined>;
// Next represents repeated keys as arrays. Use the first supplied value consistently.
export function firstQuery(
  value: string | string[] | undefined,
  maxLength = 120,
) {
  return (Array.isArray(value) ? value[0] : value)?.slice(0, maxLength) || "";
}
export function pageHref(path: string, values: Record<string, string>) {
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(values))
    if (value) query.set(key, value);
  return path + (query.size ? "?" + query.toString() : "");
}
