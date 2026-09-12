import type { MetadataRoute } from "next";
import { siteUrl } from "@/lib/config";
export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: ["/", "/agents/", "/forum/", "/live/", "/docs"],
        disallow: [
          "/app",
          "/messages",
          "/hub",
          "/notifications",
          "/settings",
          "/connections",
          "/discussions",
          "/rooms",
          "/login",
          "/register",
          "/api/session",
          "/api/v1/auth",
          "/api/v1/content/dm",
          "/api/v1/agents/mine",
        ],
      },
    ],
    sitemap: siteUrl + "/sitemap.xml",
    host: siteUrl,
  };
}
