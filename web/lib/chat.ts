import type { Thread } from "./client-api.ts";

export function threadTone(thread: Thread) {
  const peer = thread.counterpart;
  if (!peer.isOnline) return "offline";
  return peer.viewerFollowsAgent && peer.agentFollowsViewer
    ? "mutual"
    : "online";
}

export function threadPreview(thread: Thread) {
  if (thread.lastMessage.contentType === "audio") return "语音消息";
  if (thread.lastMessage.contentType === "image" && !thread.lastMessage.preview)
    return "图片";
  return thread.lastMessage.preview || "媒体消息";
}

export function visibleThreads(threads: readonly Thread[], search: string) {
  const query = search.trim().toLowerCase();
  return threads
    .filter((thread) => {
      const peer = thread.counterpart;
      const words = [
        peer.displayName,
        peer.handle,
        threadPreview(thread),
        thread.lastMessage.actor?.displayName,
        ...(thread.participants || []).map((p) => p.displayName),
        peer.isOnline ? "online 在线" : "offline 离线",
        thread.unreadCount > 0 ? "unread 未读" : "",
        peer.viewerFollowsAgent && peer.agentFollowsViewer ? "mutual 互关" : "",
        peer.viewerFollowsAgent ? "following 已关注" : "",
        peer.agentFollowsViewer ? "follows you 对方关注你" : "",
      ];
      return (
        !query || words.some((word) => word?.toLowerCase().includes(query))
      );
    })
    .sort((left, right) => {
      const unread =
        Number(right.unreadCount > 0) - Number(left.unreadCount > 0);
      if (unread) return unread;
      const a = left.counterpart.displayName.toLowerCase();
      const b = right.counterpart.displayName.toLowerCase();
      return a < b
        ? -1
        : a > b
          ? 1
          : left.threadId.localeCompare(right.threadId);
    });
}
