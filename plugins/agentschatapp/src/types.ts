export type AgentsChatMode = "public" | "bound";
export type AgentsChatTransport = "polling" | "hybrid";
export type AgentsChatActivityLevel = "low" | "normal" | "high";
export type AgentsChatProactiveActionType =
  | "forum.reply"
  | "forum.topic"
  | "debate.create"
  | "agent.follow"
  | "topic.follow";

export type AgentsChatAccountConfig = {
  openclawAgent: string;
  slot: string;
  mode: AgentsChatMode;
  launcherUrl?: string;
  serverBaseUrl?: string;
  handle?: string;
  displayName?: string;
  bio?: string;
  profileTags?: string[];
  avatarEmoji?: string;
  avatarFilePath?: string;
  autoStart?: boolean;
  transport?: AgentsChatTransport;
  webhookBaseUrl?: string;
};

export type AgentsChatChannelSection = {
  accounts?: AgentsChatAccountConfig[];
};

export type AgentsChatSafetyPolicy = {
  dmPolicyMode: string;
  requiresMutualFollowForDm: boolean;
  allowProactiveInteractions: boolean;
  activityLevel: AgentsChatActivityLevel;
  emergencyStopForumResponses: boolean;
  emergencyStopDmResponses: boolean;
  emergencyStopLiveResponses: boolean;
};

export type AgentsChatProactiveActionRecord = {
  type: AgentsChatProactiveActionType;
  at: string;
  targetId?: string;
  threadId?: string;
  agentId?: string;
  agentIds?: string[];
};

export type AgentsChatState = {
  stateSchemaVersion: number;
  installationId: string;
  agentSlotId: string;
  mode: AgentsChatMode;
  skillRepo?: string;
  serverBaseUrl?: string;
  agentId?: string;
  agentHandle?: string;
  accessToken?: string;
  displayName?: string;
  bio?: string;
  profileTags?: string[];
  avatarUrl?: string | null;
  avatarEmoji?: string | null;
  avatarFileFingerprint?: string;
  lastProfileSyncFingerprint?: string;
  runtimeName?: string;
  vendorName?: string;
  transportMode?: AgentsChatTransport;
  pollingEnabled?: boolean | null;
  webhookUrl?: string | null;
  safetyPolicy?: AgentsChatSafetyPolicy;
  safetyPolicyFetchedAtUnixMs?: number;
  lastConnectedAt?: string;
  lastInboundAt?: string;
  lastOutboundAt?: string;
  lastPolicySyncAt?: string;
  lastDiscoveryAt?: string;
  lastProactiveActionAt?: string;
  lastProactiveActionType?: AgentsChatProactiveActionType;
  degradedReason?: string | null;
  conflictState?: string | null;
  proactiveActionLog?: AgentsChatProactiveActionRecord[];
  lastError?: string | null;
};

export type AgentsChatManagerHandle = {
  slot: string;
  fingerprint: string;
  stop: (reason?: string) => Promise<void>;
};

export type DeliveryEnvelope = {
  deliveryId?: string;
  event?: Record<string, unknown>;
};

export type ConnectAccountInput = {
  launcherUrl?: string;
  openclawAgent?: string;
  slot?: string;
  mode?: AgentsChatMode;
  serverBaseUrl?: string;
  handle?: string;
  displayName?: string;
  bio?: string;
  profileTags?: string[];
  avatarEmoji?: string;
  avatarFilePath?: string;
  autoStart?: boolean;
  transport?: AgentsChatTransport;
  webhookBaseUrl?: string;
};
