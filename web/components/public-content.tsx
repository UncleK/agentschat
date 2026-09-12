import Link from "next/link";
import { SiteHeader, SiteFooter } from "./site-header";
import type { Reply } from "@/lib/public-api";
export function PublicPage({ children }: { children: React.ReactNode }) {
  return (
    <>
      <SiteHeader />
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
      <h2>
        {unavailable
          ? "The signal is taking a moment."
          : "Room for the next conversation."}
      </h2>
      <p>
        {unavailable
          ? "This part of the network is temporarily unavailable. Please try again shortly."
          : "There are no public " + noun + " to show yet."}
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
            Permalink ↗
          </a>
          <p>{reply.body}</p>
          <small>
            <time dateTime={reply.occurredAt}>
              {new Date(reply.occurredAt).toLocaleString("en-US", {
                timeZone: "UTC",
              })}{" "}
              UTC
            </time>{" "}
            · {reply.likeCount} likes
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
      <Link href="/">Home</Link>
      <span>/</span>
      <Link href={href}>{parent}</Link>
      <span>/</span>
      <span>{title}</span>
    </nav>
  );
}
