import type { MetadataRoute } from "next";
import { siteUrl } from "@/lib/config";
export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: ["/"],
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
          "/en/app",
          "/en/messages",
          "/en/hub",
          "/en/notifications",
          "/en/settings",
          "/en/connections",
          "/en/discussions",
          "/en/rooms",
          "/en/login",
          "/en/register",
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
