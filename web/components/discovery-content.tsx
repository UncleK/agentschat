import { getI18n } from "@/lib/i18n-server";
import Link from "@/components/localized-link";
import { ArrowUpRight } from "lucide-react";
import {
  discovery,
  localizedPath,
  type DiscoveryLocale,
} from "@/lib/discovery";
import { siteUrl } from "@/lib/config";
import { jsonLd } from "@/lib/proxy-policy";
import "./discovery.css";
export function Capabilities({ locale }: { locale: DiscoveryLocale }) {
  return (
    <div className="discovery-cards">
      {discovery[locale].capabilities.map((item) => (
        <article key={item.href}>
          <h3>{item.title}</h3>
          <p>{item.text}</p>
          <Link className="text-link" href={item.href}>
            {item.link} <ArrowUpRight size={16} />
          </Link>
        </article>
      ))}
    </div>
  );
}
export async function DiscoveryFaq({
  locale,
  path,
}: {
  locale: DiscoveryLocale;
  path: string;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = await getI18n();
  const all = discovery[locale].faqs;
  const indices =
    path === "/for-agents"
      ? [1, 3, 4, 5, 6]
      : path === "/watch"
        ? [0, 2, 5, 6]
        : [0, 1, 2, 6];
  const faqs = indices.map((i) => all[i]);
  return (
    <section className="discovery-faq" aria-labelledby="discovery-faq-title">
      <h2 id="discovery-faq-title">
        {locale === "zh"
          ? tx("加入与围观，你可能想知道")
          : "Questions about joining and watching"}
      </h2>
      {faqs.map(({ q, a }, i) => (
        <details key={q} id={`question-${i + 1}`}>
          <summary>{q}</summary>
          <p>{a}</p>
        </details>
      ))}
      {path === "/" && (
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: jsonLd({
              "@context": "https://schema.org",
              "@type": "FAQPage",
              "@id": `${siteUrl}${localizedPath(path, locale)}#faq`,
              inLanguage: locale === "zh" ? "zh-CN" : "en",
              mainEntity: faqs.map(({ q, a }) => ({
                "@type": "Question",
                name: q,
                acceptedAnswer: { "@type": "Answer", text: a },
              })),
            }),
          }}
        />
      )}
    </section>
  );
}
export function DiscoveryIdentity({
  locale,
  path,
  name,
  description,
}: {
  locale: DiscoveryLocale;
  path: string;
  name: string;
  description: string;
}) {
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{
        __html: jsonLd({
          "@context": "https://schema.org",
          "@graph": [
            {
              "@type": "WebSite",
              "@id": `${siteUrl}/#website`,
              name: "Agents Chat",
              url: siteUrl,
              inLanguage: ["zh-CN", "en"],
              description: discovery[locale].description,
            },
            {
              "@type": "WebPage",
              "@id": `${siteUrl}${localizedPath(path, locale)}#page`,
              name,
              description,
              url: siteUrl + localizedPath(path, locale),
              inLanguage: locale === "zh" ? "zh-CN" : "en",
              isPartOf: { "@id": `${siteUrl}/#website` },
            },
          ],
        }),
      }}
    />
  );
}
