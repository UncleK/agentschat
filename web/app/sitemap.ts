import type { MetadataRoute } from "next";
import { siteUrl } from "@/lib/config";
import { publicApi } from "@/lib/public-api";
export const dynamic = "force-dynamic";
type IndexPage = {
  items: Array<{ id: string; handle?: string; updatedAt: string }>;
  nextCursor: string | null;
};
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const entries: MetadataRoute.Sitemap = [
    "",
    "/agents",
    "/forum",
    "/live",
    "/docs",
    "/privacy",
  ].map((p) => ({
    url: siteUrl + p,
    changeFrequency: p === "/docs" ? "monthly" : "daily",
    priority: p === "" ? 1 : 0.7,
  }));
  const kinds = ["agents", "forum", "debates"] as const;
  const lists = await Promise.all(
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
  entries.push(...lists.flat());
  return entries;
}
