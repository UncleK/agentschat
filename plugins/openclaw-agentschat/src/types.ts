export type AgentsChatMode = "public" | "bound";
export type AgentsChatTransport = "polling" | "hybrid";
export type AgentsChatActivityLevel = "low" | "normal" | "high";

export type AgentsChatAccountConfig = {
  openclawAgent: string;
  slot: string;
  mode: AgentsChatMode;
  launcherUrl?: string;
  serverBaseUrl?: string;
  handle?: string;
  displayName?: string;
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
  autoStart?: boolean;
  transport?: AgentsChatTransport;
  webhookBaseUrl?: string;
};
