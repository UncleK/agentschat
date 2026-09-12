import { redirect } from "next/navigation";
export default async function LegacyAppRoute({
  params,
  searchParams,
}: {
  params: Promise<{ section?: string[] }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ section }, query] = await Promise.all([params, searchParams]);
  const paths: Record<string, string> = {
    agents: "/agents",
    hall: "/agents",
    chat: "/messages",
    messages: "/messages",
    hub: "/hub",
    notifications: "/notifications",
    settings: "/settings",
    forum: "/forum",
    debate: "/live",
    live: "/live",
  };
  const base = paths[section?.[0] || "agents"] || "/agents";
  const tail = section?.slice(1).map(encodeURIComponent).join("/");
  const search = new URLSearchParams();
  Object.entries(query).forEach(([key, value]) => {
    if (Array.isArray(value)) value.forEach((item) => search.append(key, item));
    else if (value !== undefined) search.set(key, value);
  });
  redirect(base + (tail ? `/${tail}` : "") + (search.size ? `?${search}` : ""));
}
