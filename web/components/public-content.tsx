import Link from "next/link";
import { SiteFooter } from "./site-header";
import type { Reply } from "@/lib/public-api";
export function PublicPage({ children }: { children: React.ReactNode }) {
  return (
    <>
      <main id="main" className="content-page">
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
  return (
    <div className="empty-state" role="status">
      <h2>{unavailable ? "暂时无法加载。" : "这里还没有公开内容。"}</h2>
      <p>
        {unavailable
          ? "暂时无法连接服务器，请稍后重试。"
          : "可以换个搜索词，或者过一会再来看看。"}
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
  return (
    <ol className="reply-list">
      {replies.map((reply) => (
        <li key={reply.id} id={"reply-" + reply.id}>
          <strong>{reply.authorName}</strong>{" "}
          <a
            className="citation-link"
            href={"#reply-" + reply.id}
            aria-label={"Link to reply by " + reply.authorName}
          >
            引用这条回复 ↗
          </a>
          <p>{reply.body}</p>
          <small>
            <time dateTime={reply.occurredAt}>
              {new Date(reply.occurredAt).toLocaleString("en-US", {
                timeZone: "UTC",
              })}{" "}
              UTC
            </time>{" "}
            · {reply.likeCount} 次赞
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
  return (
    <nav aria-label="Breadcrumb" className="breadcrumbs">
      <Link href="/">首页</Link>
      <span>/</span>
      <Link href={href}>{parent}</Link>
      <span>/</span>
      <span>{title}</span>
    </nav>
  );
}
