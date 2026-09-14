"use client";
import { useI18n } from "@/components/locale-provider";
import Link from "@/components/localized-link";
import { SiteFooter } from "./site-header";
import type { Reply } from "@/lib/public-api";
export function PublicPage({
  children,
  className = "",
  lang,
}: {
  children: React.ReactNode;
  className?: string;
  lang?: string;
}) {
  return (
    <>
      <main id="main" lang={lang} className={`content-page ${className}`}>
        {children}
      </main>
      <SiteFooter />
    </>
  );
}
export function Empty({
  unavailable = false,
  noun = "content",
}: {
  unavailable?: boolean;
  noun?: string;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  return (
    <div className="empty-state" role="status">
      <h2>{unavailable ? tx("暂时无法加载。") : tx("这里还没有公开内容。")}</h2>
      <p>
        {unavailable
          ? tx("暂时无法连接服务器，请稍后重试。")
          : tx("可以换个搜索词，或者过一会再来看看。")}
      </p>
    </div>
  );
}
export function Tags({ tags }: { tags: string[] }) {
  return (
    <div className="tags">
      {tags.map((tag) => (
        <span className="tag" key={tag}>
          {tag}
        </span>
      ))}
    </div>
  );
}
export function Replies({ replies }: { replies: Reply[] }) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  return (
    <ol className="reply-list">
      {replies.map((reply) => (
        <li key={reply.id} id={"reply-" + reply.id}>
          <strong>{reply.authorName}</strong>{" "}
          <a
            className="citation-link"
            href={"#reply-" + reply.id}
            aria-label={tx("引用 {0} 的回复", reply.authorName)}
          >
            {tx("引用这条回复 ↗")}
          </a>
          <p>{reply.body}</p>
          <small>
            <time dateTime={reply.occurredAt}>
              {new Date(reply.occurredAt).toLocaleString(uiLang, {
                timeZone: "UTC",
              })}{" "}
              {tx(" UTC ")}
            </time>
            {tx("· {0}次赞", reply.likeCount)}
          </small>
          {reply.children?.length > 0 && <Replies replies={reply.children} />}
        </li>
      ))}
    </ol>
  );
}
export function Breadcrumbs({
  parent,
  href,
  title,
}: {
  parent: string;
  href: string;
  title: string;
}) {
  const { t: tx, locale: uiLocale, lang: uiLang } = useI18n();
  return (
    <nav aria-label={tx("面包屑导航")} className="breadcrumbs">
      <Link href="/">{tx("首页")}</Link>
      <span>/</span>
      <Link href={href}>{parent}</Link>
      <span>/</span>
      <span>{title}</span>
    </nav>
  );
}
