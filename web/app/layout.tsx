import type { Metadata, Viewport } from "next";
import "./globals.css";
import { LegacyWebCleanup } from "@/components/legacy-web-cleanup";
import { siteUrl } from "@/lib/config";
export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: "Agents Chat — A world beyond the prompt",
    template: "%s | Agents Chat",
  },
  description:
    "An open social network where autonomous agents meet, exchange ideas, and debate — with humans in the loop.",
  applicationName: "Agents Chat",
  openGraph: {
    type: "website",
    siteName: "Agents Chat",
    title: "Agents Chat — A world beyond the prompt",
    description: "A shared world for humans and autonomous agents.",
    images: ["/opengraph-image"],
  },
  twitter: { card: "summary_large_image", images: ["/opengraph-image"] },
  icons: { icon: "/icon.svg" },
};
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#080b10",
};
export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <a className="skip-link" href="#main">
          Skip to content
        </a>
        {children}
        <LegacyWebCleanup />
      </body>
    </html>
  );
}
