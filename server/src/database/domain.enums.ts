export enum AuthProvider {
  Email = 'email',
  Google = 'google',
  GitHub = 'github',
}

export enum SubjectType {
  Human = 'human',
  Agent = 'agent',
}

export enum AgentOwnerType {
  Human = 'human',
  Self = 'self',
}

export enum AgentStatus {
  Offline = 'offline',
  Online = 'online',
  Debating = 'debating',
  Suspended = 'suspended',
}

export enum AgentDmAcceptanceMode {
  Open = 'open',
  FollowedOnly = 'followed_only',
  ApprovalRequired = 'approval_required',
  Closed = 'closed',
}

export enum AgentActivityLevel {
  Low = 'low',
  Normal = 'normal',
  High = 'high',
}

export enum ConnectionTransportMode {
  Webhook = 'webhook',
  Polling = 'polling',
  Hybrid = 'hybrid',
}

export enum ThreadContextType {
  DirectMessage = 'dm',
  ForumTopic = 'forum_topic',
  DebateSpectator = 'debate_spectator',
}

export enum ThreadVisibility {
  Private = 'private',
  Public = 'public',
}

export enum ThreadParticipantRole {
  Member = 'member',
  Host = 'host',
  Spectator = 'spectator',
}

export enum EventActorType {
  Human = 'human',
  Agent = 'agent',
  System = 'system',
}

export enum EventContentType {
  None = 'none',
  Text = 'text',
  Markdown = 'markdown',
  Code = 'code',
  Image = 'image',
}

export enum AssetKind {
  Image = 'image',
}

export enum AssetUploadStatus {
  Pending = 'pending',
  Uploaded = 'uploaded',
}

export enum AssetModerationStatus {
  Pending = 'pending',
  Approved = 'approved',
  Rejected = 'rejected',
}

export enum DebateSessionStatus {
  Pending = 'pending',
  Live = 'live',
  Paused = 'paused',
  Ended = 'ended',
  Archived = 'archived',
}

export enum DebateSeatStatus {
  Reserved = 'reserved',
  Occupied = 'occupied',
  Vacant = 'vacant',
  Replacing = 'replacing',
}

export enum DebateSeatStance {
  Pro = 'pro',
  Con = 'con',
}

export enum DebateTurnStatus {
  Pending = 'pending',
  Completed = 'completed',
  Skipped = 'skipped',
  Missed = 'missed',
}

export enum FollowTargetType {
  Agent = 'agent',
  Topic = 'topic',
  Debate = 'debate',
}

export enum DeliveryStatus {
  Pending = 'pending',
  Sent = 'sent',
  Acked = 'acked',
  Retrying = 'retrying',
  Failed = 'failed',
  DeadLetter = 'dead_letter',
}

export enum DeliveryChannel {
  Webhook = 'webhook',
  Polling = 'polling',
}

export enum FederationActionStatus {
  Accepted = 'accepted',
  Processing = 'processing',
  Succeeded = 'succeeded',
  Rejected = 'rejected',
  Failed = 'failed',
}

export enum ClaimRequestStatus {
  Pending = 'pending',
  Confirmed = 'confirmed',
  Expired = 'expired',
  Rejected = 'rejected',
}

export enum ModerationTargetType {
  User = 'user',
  Agent = 'agent',
  Thread = 'thread',
  Event = 'event',
  DebateSession = 'debate_session',
}
