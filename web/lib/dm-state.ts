export const ACTIVE_AGENT_KEY = "agents-chat.active-agent";

export function readActiveAgent(): string {
  try {
    return sessionStorage.getItem(ACTIVE_AGENT_KEY) || "";
  } catch {
    return "";
  }
}
export function rememberActiveAgent(id: string) {
  try {
    if (sessionStorage.getItem(ACTIVE_AGENT_KEY) === id) return;
    sessionStorage.setItem(ACTIVE_AGENT_KEY, id);
    window.dispatchEvent(new Event("agents-chat:active-agent-changed"));
  } catch {}
}
export function chooseActiveAgent(
  agents: ReadonlyArray<{ id: string; status?: string }>,
  ...preferences: Array<string | null | undefined>
) {
  const available = agents.filter((agent) => agent.status !== "suspended");
  return (
    preferences.find((id) => available.some((agent) => agent.id === id)) ||
    available[0]?.id ||
    ""
  );
}
export function messagePath(threadId?: string, agentId?: string) {
  const path =
    "/messages" + (threadId ? "/" + encodeURIComponent(threadId) : "");
  return path + (agentId ? "?agent=" + encodeURIComponent(agentId) : "");
}
export async function resolveThreadAgent(
  agentIds: readonly string[],
  check: (agentId: string) => Promise<unknown>,
) {
  for (const id of agentIds) {
    try {
      await check(id);
      return id;
    } catch (error) {
      if (
        !(
          error &&
          typeof error === "object" &&
          "status" in error &&
          error.status === 404
        )
      )
        throw error;
    }
  }
  throw new Error("这段对话不属于你的可用 Agent，或已不可访问。");
}

export type DatedMessage = { eventId: string; occurredAt: string };
export type HistoryPage<T> = { messages: T[]; nextCursor: string | null };
type DatedThread = { threadId: string; lastMessage: { occurredAt: string } };
export function nextThreadCursor(
  previous: readonly DatedThread[],
  incoming: readonly DatedThread[],
  cursor: string | null | undefined,
  incomingCursor: string | null,
) {
  if (cursor === undefined || !previous.length) return incomingCursor;
  if (!incoming.length || !incomingCursor) return cursor;
  const newestKnown = Math.max(
    ...previous.map((thread) => Date.parse(thread.lastMessage.occurredAt)),
  );
  const oldestIncoming = Math.min(
    ...incoming.map((thread) => Date.parse(thread.lastMessage.occurredAt)),
  );
  const changed = incoming.some(
    (thread) =>
      !previous.some(
        (old) =>
          old.threadId === thread.threadId &&
          old.lastMessage.occurredAt === thread.lastMessage.occurredAt,
      ),
  );
  return changed && oldestIncoming >= newestKnown ? incomingCursor : cursor;
}
export function mergeMessages<T extends DatedMessage>(
  previous: readonly T[],
  incoming: readonly T[],
): T[] {
  const byId = new Map(previous.map((message) => [message.eventId, message]));
  for (const message of incoming) byId.set(message.eventId, message);
  return [...byId.values()].sort(
    (a, b) =>
      Date.parse(a.occurredAt) - Date.parse(b.occurredAt) ||
      a.eventId.localeCompare(b.eventId),
  );
}

/** Walk backward from the latest page until it overlaps our last known history. */
export async function bridgeMessageGap<T extends DatedMessage>(
  previous: readonly T[],
  latest: HistoryPage<T>,
  load: (cursor: string) => Promise<HistoryPage<T>>,
): Promise<HistoryPage<T>> {
  if (!previous.length) return latest;
  const known = new Set(previous.map((message) => message.eventId));
  const visited = new Set<string>();
  let page = latest;
  let messages = latest.messages;
  while (
    page.nextCursor &&
    !page.messages.some((message) => known.has(message.eventId))
  ) {
    const cursor = page.nextCursor;
    if (visited.has(cursor))
      throw new Error("服务器返回了重复的消息游标，请重试。");
    visited.add(cursor);
    page = await load(cursor);
    messages = mergeMessages(page.messages, messages);
  }
  return { messages, nextCursor: page.nextCursor };
}
