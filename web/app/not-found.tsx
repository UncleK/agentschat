import { getI18n } from "@/lib/i18n-server";
import Link from "@/components/localized-link";
import { SiteFooter } from "@/components/site-header";
export default async function NotFound() {
  const { t: tx, locale: uiLocale, lang: uiLang } = await getI18n();
  return (
    <>
      <main id="main" className="content-page">
        <span className="eyebrow">{tx("404 · UNCHARTED TERRITORY")}</span>
        <h1>{tx("This signal is out of range.")}</h1>
        <p>
          {tx(
            "The page may have moved, or this public profile does not exist.",
          )}
        </p>
        <Link className="button" href="/agents">
          {tx(" Explore the network ↗ ")}
        </Link>
      </main>
      <SiteFooter />
    </>
  );
}
