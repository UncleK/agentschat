export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export async function request<T>(
  url: string,
  init: RequestInit = {},
): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  if (init.body && !(init.body instanceof FormData))
    headers.set("Content-Type", "application/json");
  let response: Response;
  try {
    response = await fetch(url, {
      ...init,
      headers,
      credentials: "same-origin",
      cache: "no-store",
    });
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") throw error;
    throw new ApiError("无法连接服务器，请检查网络后重试。", 0);
  }
  const text = await response.text();
  let body: unknown;
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    throw new ApiError(
      "服务器返回了无法读取的响应，请稍后重试。",
      response.status,
    );
  }
  if (!response.ok) {
    if (
      typeof window !== "undefined" &&
      response.status === 401 &&
      url.startsWith("/api/v1/") &&
      !url.startsWith("/api/v1/auth/")
    )
      window.dispatchEvent(new Event("agents-chat:session-expired"));
    const data = body as { message?: string | string[]; error?: string };
    const message = Array.isArray(data.message)
      ? data.message.join("；")
      : data.message;
    throw new ApiError(
      message || data.error || `请求失败（${response.status}）`,
      response.status,
    );
  }
  return body as T;
}

export function api<T>(path: string, init?: RequestInit) {
  return request<T>(`/api/v1${path}`, init);
}
export function mutate<T>(path: string, body: unknown = {}, method = "POST") {
  return api<T>(path, { method, body: JSON.stringify(body) });
}
export function query(
  path: string,
  values: Record<string, string | undefined>,
) {
  const params = new URLSearchParams();
  Object.entries(values).forEach(([key, value]) => {
    if (value) params.set(key, value);
  });
  return params.size ? `${path}?${params}` : path;
}
export function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "操作失败，请重试。";
}
export function mediaUrl(value?: string | null): string | undefined {
  if (!value) return undefined;
  if (value.startsWith("/api/v1/")) return value;
  if (value.startsWith("/assets/") || value.startsWith("/agents/"))
    return `/api/v1${value}`;
  try {
    const url = new URL(value);
    if (!["http:", "https:"].includes(url.protocol)) return undefined;
    if (url.pathname.startsWith("/api/v1/"))
      return `${url.pathname}${url.search}`;
    return value;
  } catch {
    return undefined;
  }
}
export type User = {
  id: string;
  email: string;
  username: string;
  displayName: string;
  emailVerified: boolean;
};
export type Session = {
  user: User;
  session?: { authenticated: boolean };
  recommendedActiveAgentId?: string | null;
};
export async function optionalSession(
  init?: RequestInit,
): Promise<Session | null> {
  const status = await request<{ authenticated: boolean }>(
    "/api/session?status=1",
    init,
  );
  return status.authenticated ? request<Session>("/api/session", init) : null;
}
export type Policy = {
  dmPolicyMode: string;
  requiresMutualFollowForDm: boolean;
  allowProactiveInteractions: boolean;
  activityLevel: string;
  emergencyStopForumResponses: boolean;
  emergencyStopDmResponses: boolean;
  emergencyStopLiveResponses: boolean;
};
export type Agent = {
  id: string;
  handle: string;
  displayName: string;
  avatarUrl?: string;
  avatarEmoji?: string;
  bio?: string;
  status: string;
  ownerType?: string;
  profileTags?: string[];
  followerCount?: number;
  safetyPolicy?: Policy;
  runtimeName?: string;
  lastHeartbeatAt?: string;
  relationship?: { viewerFollowsAgent: boolean; agentFollowsViewer: boolean };
  dmPolicy?: { directMessageAllowed: boolean; blockedReasons: string[] };
};
export type Claim = {
  claimRequestId: string;
  agentId: string;
  displayName: string;
  status: string;
  expiresAt: string;
};
export type Mine = {
  agents: Agent[];
  claimableAgents: Agent[];
  pendingClaims: Claim[];
};
export type Thread = {
  threadId: string;
  counterpart: {
    type?: string;
    id: string;
    displayName: string;
    avatarEmoji?: string;
    isOnline?: boolean;
  };
  lastMessage: { preview: string; occurredAt: string };
  unreadCount: number;
  threadUsage?: string;
};
export type Asset = {
  id: string;
  url?: string;
  kind: string;
  mimeType: string;
};
export type Message = {
  eventId: string;
  actor: { id: string; displayName: string; type: string };
  contentType: string;
  content?: string;
  asset?: Asset | null;
  occurredAt: string;
  metadata?: {
    voice?: {
      transcriptLanguage?: string;
      source?: string;
      durationMs?: number;
    };
  };
};
export type Participant = {
  type: "human" | "agent";
  id: string;
  displayName: string;
  handle?: string | null;
  avatarUrl?: string | null;
  avatarEmoji?: string | null;
  isOnline: boolean;
  role: string;
  ownerUserId?: string | null;
};
export type RuntimeStatus = {
  agentId: string;
  observedAt: string;
  status: string;
  presence: {
    state: "recent" | "stale" | "never_seen" | "disconnected";
    lastSeenAt: string | null;
    lastHeartbeatAt: string | null;
    staleAfterSeconds: number;
  };
  connection: {
    configured: boolean;
    transportMode: "webhook" | "polling" | "hybrid" | null;
    pollingEnabled: boolean;
    webhookConfigured: boolean;
    protocolVersion: string | null;
  };
  deliveries: {
    pending: number;
    sent: number;
    retrying: number;
    deadLetter: number;
    acked: number;
    lastAttemptAt: string | null;
    lastAckedAt: string | null;
    nextAttemptAt: string | null;
    lastError: {
      message: string;
      occurredAt: string | null;
      deliveryId: string;
    } | null;
  };
};
export type Reply = {
  id: string;
  authorName: string;
  body: string;
  occurredAt?: string;
  likeCount: number;
  viewerHasLiked: boolean;
  isHuman: boolean;
  children?: Reply[];
};
export type Topic = {
  threadId: string;
  title: string;
  summary: string;
  rootBody: string;
  authorName: string;
  replyCount: number;
  participantCount: number;
  tags: string[];
  replies?: Reply[];
};
export type Debate = {
  debateSessionId: string;
  topic: string;
  proStance: string;
  conStance: string;
  status: string;
  host: { id: string; displayName: string; type: string };
  freeEntry: boolean;
  seats: {
    id: string;
    stance: string;
    status: string;
    agent?: { id: string; displayName: string };
  }[];
  formalTurns: {
    id: string;
    turnNumber: number;
    stance: string;
    status: string;
    event?: { content: string; occurredAt: string };
  }[];
  spectatorFeed: {
    id: string;
    actorDisplayName: string;
    content: string;
    occurredAt: string;
  }[];
};
export type Notice = {
  id: string;
  kind?: string;
  threadId?: string;
  readAt?: string;
  createdAt?: string;
  payload: {
    title?: string;
    message?: string;
    content?: string;
    preview?: string;
    actorDisplayName?: string;
    actorAgentId?: string | null;
    actorUserId?: string | null;
    eventType?: string;
    metadata?: {
      authorName?: string;
      counterpartDisplayName?: string;
      topic?: string;
    };
    debateSessionId?: string;
    targetType?: string;
    targetId?: string;
  };
};
