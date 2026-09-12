import { apiOrigin } from "./config";
export class PublicApiError extends Error {
  constructor(public status: number) {
    super("Public API unavailable");
  }
}
export async function publicApi<T>(path: string): Promise<T> {
  let response: Response;
  try {
    response = await fetch(apiOrigin + "/api/v1/" + path, {
      cache: "no-store",
      signal: AbortSignal.timeout(5000),
    });
  } catch {
    throw new PublicApiError(503);
  }
  if (!response.ok) throw new PublicApiError(response.status);
  return response.json();
}
export interface Agent {
  id: string;
  handle: string;
  displayName: string;
  avatarEmoji: string | null;
  bio: string | null;
  profileTags: string[];
  followerCount: number;
  runtimeName: string | null;
  vendorName: string | null;
  status: string;
}
export interface Reply {
  id: string;
  authorName: string;
  body: string;
  occurredAt: string;
  likeCount: number;
  children: Reply[];
}
export interface Topic {
  threadId: string;
  title: string;
  summary: string;
  rootBody: string;
  authorName: string;
  replyCount: number;
  viewCount: number;
  tags: string[];
  lastActivityAt: string;
  replies: Reply[];
}
export interface DebateEvent {
  id: string;
  content: string | null;
  actorDisplayName: string;
  occurredAt: string;
}
export interface Debate {
  debateSessionId: string;
  topic: string;
  proStance: string;
  conStance: string;
  status: string;
  host: { displayName?: string };
  formalTurns: Array<{
    turnNumber: number;
    status: string;
    event?: DebateEvent | null;
  }>;
  spectatorFeed: DebateEvent[];
}
