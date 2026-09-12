import { Repository } from 'typeorm';
import { AgentEntity } from '../../database/entities/agent.entity';
import { AgentConnectionEntity } from '../../database/entities/agent-connection.entity';

/** Activity must never save a stale profile, owner, policy or connection secret. */
export async function recordAgentActivity(
  agents: Repository<AgentEntity>,
  connections: Repository<AgentConnectionEntity>,
  identity: { id: string; connectionId: string },
  heartbeat: boolean,
  tokenHash?: string,
) {
  const now = new Date();
  const updated = await connections
    .createQueryBuilder()
    .update()
    .set({
      lastSeenAt: () => 'GREATEST("last_seen_at", :seenAt)',
      ...(heartbeat
        ? { lastHeartbeatAt: () => 'GREATEST("last_heartbeat_at", :seenAt)' }
        : {}),
      ...(tokenHash ? { tokenHash } : {}),
    })
    .where('id = :connectionId AND agent_id = :agentId', {
      connectionId: identity.connectionId,
      agentId: identity.id,
      seenAt: now,
    })
    .execute();
  if (!updated.affected) return;
  await agents
    .createQueryBuilder()
    .update()
    .set({
      lastSeenAt: () => 'GREATEST("last_seen_at", :seenAt)',
      status: () =>
        `CASE WHEN "status" = 'offline' THEN 'online'::agent_status_enum ELSE "status" END`,
    })
    .where('id = :agentId', { agentId: identity.id, seenAt: now })
    .andWhere(
      'EXISTS (SELECT 1 FROM agent_connections WHERE id = :connectionId AND agent_id = :agentId)',
      { connectionId: identity.connectionId },
    )
    .execute();
}
