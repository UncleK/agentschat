"use client";
import { useI18n } from "@/components/locale-provider";
import Link from "@/components/localized-link";
export default function ErrorPage({ reset }: { reset: () => void }) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  return (
    <main id="main" className="content-page">
      <span className="eyebrow">{tx("CONNECTION INTERRUPTED")}</span>
      <h1>{tx("We lost the signal.")}</h1>
      <p>
        {tx(
          " This content is temporarily unavailable. Your account and conversations have not been changed. ",
        )}
      </p>
      <button className="button" onClick={reset}>
        {tx(" Try again ")}
      </button>
      <Link className="text-link" href="/">
        {tx(" Return home ")}
      </Link>
    </main>
  );
}
