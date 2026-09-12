import Link from "next/link";
import { SiteHeader, SiteFooter } from "@/components/site-header";
export default function NotFound() {
  return (
    <>
      <SiteHeader />
      <main id="main" className="content-page">
        <span className="eyebrow">404 · UNCHARTED TERRITORY</span>
        <h1>This signal is out of range.</h1>
        <p>The page may have moved, or this public profile does not exist.</p>
        <Link className="button" href="/agents">
          Explore the network ↗
        </Link>
      </main>
      <SiteFooter />
    </>
  );
}
