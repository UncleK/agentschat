import type { ReactNode } from "react";
import { ArrowUpRight, BookOpen, ShieldCheck, FileCode2 } from "lucide-react";
import { PublicPage } from "./public-content";
import "./guide-layout.css";

type GuideItem = { id: string; label: string };
export function GuidePage({
  title,
  lead,
  eyebrow,
  lang,
  kind = "docs",
  items,
  contentsLabel,
  actions,
  children,
}: {
  title: string;
  lead: string;
  eyebrow: string;
  lang: string;
  kind?: "docs" | "privacy" | "reading";
  items: GuideItem[];
  contentsLabel: string;
  actions?: ReactNode;
  children: ReactNode;
}) {
  const Icon =
    kind === "privacy"
      ? ShieldCheck
      : kind === "reading"
        ? FileCode2
        : BookOpen;
  return (
    <PublicPage className={`guide-page guide-${kind}`} lang={lang}>
      <header className="guide-hero">
        <span className="guide-hero-icon" aria-hidden="true">
          <Icon size={34} strokeWidth={1.5} />
        </span>
        <p className="eyebrow">{eyebrow}</p>
        <h1>{title}</h1>
        <p className="lead">{lead}</p>
        {actions && <div className="guide-actions">{actions}</div>}
      </header>
      <div className="guide-layout">
        <nav className="guide-toc" aria-label={contentsLabel}>
          <p>{contentsLabel}</p>
          {items.map((item, index) => (
            <a key={item.id} href={`#${item.id}`}>
              <span>{String(index + 1).padStart(2, "0")}</span>
              {item.label}
              <ArrowUpRight size={13} />
            </a>
          ))}
        </nav>
        <div className="guide-content">{children}</div>
      </div>
    </PublicPage>
  );
}

export function GuideSection({
  id,
  title,
  number,
  children,
}: {
  id: string;
  title: string;
  number: string;
  children: ReactNode;
}) {
  return (
    <section id={id} className="guide-section">
      <header>
        <span className="guide-section-number">{number}</span>
        <h2>{title}</h2>
      </header>
      <div className="guide-section-body">{children}</div>
    </section>
  );
}
