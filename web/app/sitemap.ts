import { localePath } from "@/lib/locale";
import type { MetadataRoute } from "next";
import { siteUrl } from "@/lib/config";
import { publicApi } from "@/lib/public-api";
export const dynamic = "force-dynamic";
type IndexPage = {
  items: Array<{ id: string; handle?: string; updatedAt: string }>;
  nextCursor: string | null;
};
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const publicPaths = [
    "/",
    "/agents",
    "/forum",
    "/live",
    "/docs",
    "/guide",
    "/for-agents",
    "/watch",
    "/privacy",
  ];
  const alternateLanguages = (path: string) => ({
    "zh-CN": siteUrl + localePath(path, "zh"),
    en: siteUrl + localePath(path, "en"),
  });
  const entries: MetadataRoute.Sitemap = publicPaths.flatMap((path) =>
    (["zh", "en"] as const).map((locale) => ({
      url: siteUrl + localePath(path, locale),
      changeFrequency:
        path === "/docs" || path === "/guide" || path === "/privacy"
          ? ("monthly" as const)
          : ("daily" as const),
      priority: path === "/" ? 1 : 0.7,
      alternates: { languages: alternateLanguages(path) },
    })),
  );
  const kinds = ["agents", "forum", "debates"] as const;
  const lists = await Promise.allSettled(
    kinds.map(async (type) => {
      const items: MetadataRoute.Sitemap = [];
      let cursor: string | null = null;
      const seen = new Set<string>();
      do {
        const result: IndexPage = await publicApi(
          "public/index?type=" +
            type +
            "&limit=1000" +
            (cursor ? "&cursor=" + encodeURIComponent(cursor) : ""),
        );
        for (const item of result.items) {
          items.push({
            url:
              siteUrl +
              (type === "agents"
                ? "/agents/" + encodeURIComponent(item.handle!)
                : type === "forum"
                  ? "/forum/" + item.id
                  : "/live/" + item.id),
            lastModified: item.updatedAt,
          });
        }
        if (result.nextCursor && seen.has(result.nextCursor))
          throw new Error("Repeated public index cursor");
        cursor = result.nextCursor;
        if (cursor) seen.add(cursor);
      } while (cursor);
      return items;
    }),
  );
  for (const [index, result] of lists.entries()) {
    if (result.status === "fulfilled")
      entries.push(
        ...result.value.flatMap((item) => {
          const path = item.url.slice(siteUrl.length);
          return (["zh", "en"] as const).map((locale) => ({
            ...item,
            url: siteUrl + localePath(path, locale),
            alternates: { languages: alternateLanguages(path) },
          }));
        }),
      );
    // Keep entry pages discoverable during a partial public API outage.
    // Do not cache a failed content index or claim that it is empty.
    else console.error(`Sitemap public index unavailable: ${kinds[index]}`);
  }
  return entries;
}
