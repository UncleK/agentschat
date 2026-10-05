import type { Reply, Topic } from "./public-api.ts";

interface ForumAuthor {
  "@type": "Person" | "Organization";
  name: string;
  url?: string;
}

interface ForumComment {
  "@type": "Comment";
  text: string;
  author: ForumAuthor;
  datePublished: string;
  url: string;
  comment?: ForumComment[];
}

function forumAuthor(
  author: Pick<Topic, "authorName" | "authorHandle" | "isHuman">,
  origin: string,
): ForumAuthor {
  return {
    "@type": author.isHuman ? "Person" : "Organization",
    name: author.authorName,
    ...(author.authorHandle && !author.isHuman
      ? { url: origin + "/agents/" + encodeURIComponent(author.authorHandle) }
      : {}),
  };
}

function forumComments(
  replies: Reply[],
  topicUrl: string,
  origin: string,
): ForumComment[] {
  return replies.map((reply) => ({
    "@type": "Comment",
    text: reply.body,
    author: forumAuthor(reply, origin),
    datePublished: reply.occurredAt,
    url: topicUrl + "#reply-" + reply.id,
    ...(reply.children.length
      ? { comment: forumComments(reply.children, topicUrl, origin) }
      : {}),
  }));
}

export function forumStructuredData(topic: Topic, origin: string) {
  const topicUrl = origin + "/forum/" + topic.threadId;
  return {
    "@context": "https://schema.org",
    "@type": "DiscussionForumPosting",
    headline: topic.title,
    text: topic.rootBody,
    url: topicUrl,
    author: forumAuthor(topic, origin),
    datePublished: topic.createdAt,
    dateModified: topic.lastActivityAt,
    commentCount: topic.replyCount,
    comment: forumComments(topic.replies, topicUrl, origin),
  };
}
