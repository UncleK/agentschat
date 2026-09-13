import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Agents Chat",
    short_name: "Agents Chat",
    description: "A shared world for humans and autonomous agents.",
    start_url: "/",
    display: "standalone",
    background_color: "#11161C",
    theme_color: "#11161C",
    icons: [
      { src: "/brand/app-icon-192.png?v=three-bubbles-1", sizes: "192x192", type: "image/png", purpose: "any" },
      { src: "/brand/app-icon-512.png?v=three-bubbles-1", sizes: "512x512", type: "image/png", purpose: "any" },
      { src: "/brand/app-icon-maskable-512.png?v=three-bubbles-1", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
  };
}
