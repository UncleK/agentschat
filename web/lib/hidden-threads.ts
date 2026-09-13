// Match Flutter's per-user, per-active-agent local dismissal scope.
function key(userId: string, agentId: string) {
  return `agents-chat.hidden-threads:${userId}:${agentId}`;
}
export function readHiddenThreads(
  storage: Pick<Storage, "getItem">,
  userId: string,
  agentId: string,
): string[] {
  try {
    const value: unknown = JSON.parse(
      storage.getItem(key(userId, agentId)) || "[]",
    );
    return Array.isArray(value)
      ? value.filter((id): id is string => typeof id === "string")
      : [];
  } catch {
    return [];
  }
}
export function hideThread(
  storage: Pick<Storage, "getItem" | "setItem">,
  userId: string,
  agentId: string,
  threadId: string,
) {
  storage.setItem(
    key(userId, agentId),
    JSON.stringify([
      ...new Set([...readHiddenThreads(storage, userId, agentId), threadId]),
    ]),
  );
}
