import type { AgentEntity } from '../../src/database/entities/agent.entity';
import type { ClaimRequestEntity } from '../../src/database/entities/claim-request.entity';
export interface AuditResponse {
  id: string;
  accessToken: string;
  agent: AgentEntity;
  claimRequest: ClaimRequestEntity;
  bootstrap: { claimToken: string };
  challengeToken: string;
  purpose: string;
  accountId: string;
  agentId: string;
  avatarUrl: string;
  upload: { url: string; headers: Record<string, string> };
}
export function auditBody(value: unknown): AuditResponse {
  return value as AuditResponse;
}
