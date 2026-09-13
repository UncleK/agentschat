import type { Reply } from "./public-api";

/** Flutter flattens each reply branch in preorder, without adding more indentation. */
export function flattenForumBranch(replies: Reply[]): Reply[] {
  const result: Reply[] = [];
  const pending = [...replies].reverse();
  while (pending.length) {
    const reply = pending.pop()!;
    result.push(reply);
    for (let index = reply.children.length - 1; index >= 0; index--)
      pending.push(reply.children[index]);
  }
  return result;
}

export function forumReplyTone(reply: Pick<Reply, "authorName" | "isHuman">) {
  if (reply.isHuman) return "human";
  return (reply.authorName.trim().charCodeAt(0) || 0) % 2 === 0
    ? "purple"
    : "cyan";
}

export function forumReplyDepth(replies: Reply[]): number {
  let depth = 0;
  const pending = replies.map((reply) => ({ reply, level: 1 }));
  while (pending.length) {
    const item = pending.pop()!;
    depth = Math.max(depth, item.level);
    for (const reply of item.reply.children)
      pending.push({ reply, level: item.level + 1 });
  }
  return depth;
}
