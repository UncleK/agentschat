import type { DataSource } from 'typeorm';
import { AgentConnectionEntity } from './entities/agent-connection.entity';
import {
  participationSummary,
  type ContinuousParticipation,
} from './continuous-participation';

interface HealthRow {
  connectionId: string | null;
  tokenHash: string | null;
  webhookUrl: string | null;
  webhookSecretHash: string | null;
  participationRecord: ContinuousParticipation | null;
  agentId: string;
  handle: string;
  status: string;
  transportMode: string | null;
  lastSeenAt: Date | null;
  webhookConfigured: boolean;
  webhookBlockedUntil: Date | null;
  awaitingPoll: number;
  awaitingAck: number;
  repeatedPolls: number;
  pendingPush: number;
  retryingPush: number;
  expiredAwaitingSweep: number;
  deadLetter: number;
  acked: number;
  archived: number;
  maxAttempts: number;
  oldestOutstandingAt: Date | null;
  newDeadLetters24h: number;
}

export async function readDeliveryHealth(
  database: DataSource,
  now = new Date(),
) {
  const rows = await database.query<HealthRow[]>(
    `SELECT a.id AS "agentId", a.handle, a.status,
       c.transport_mode AS "transportMode",
       c.id AS "connectionId", c.token_hash AS "tokenHash", c.webhook_url AS "webhookUrl",
       c.webhook_secret_hash AS "webhookSecretHash", c.continuous_participation AS "participationRecord",
       GREATEST(a.last_seen_at, c.last_seen_at, c.last_heartbeat_at) AS "lastSeenAt",
       COALESCE(c.transport_mode IN ('webhook', 'hybrid') AND c.webhook_url IS NOT NULL
         AND c.webhook_secret IS NOT NULL, false) AS "webhookConfigured",
       c.webhook_blocked_until AS "webhookBlockedUntil",
       COUNT(d.id) FILTER (WHERE d.status = 'pending' AND d.delivery_channel = 'polling'
         AND d.replay_expires_at > $1)::int AS "awaitingPoll",
       COUNT(d.id) FILTER (WHERE d.status IN ('sent', 'retrying') AND d.delivery_channel = 'polling'
         AND d.replay_expires_at > $1)::int AS "awaitingAck",
       COUNT(d.id) FILTER (WHERE d.status = 'retrying' AND d.delivery_channel = 'polling'
         AND d.replay_expires_at > $1)::int AS "repeatedPolls",
       COUNT(d.id) FILTER (WHERE d.status IN ('pending', 'sent') AND d.delivery_channel = 'webhook'
         AND d.replay_expires_at > $1)::int AS "pendingPush",
       COUNT(d.id) FILTER (WHERE d.status = 'retrying' AND d.delivery_channel = 'webhook'
         AND d.replay_expires_at > $1)::int AS "retryingPush",
       COUNT(d.id) FILTER (WHERE d.status IN ('pending', 'sent', 'retrying')
         AND d.replay_expires_at <= $1)::int AS "expiredAwaitingSweep",
       COUNT(d.id) FILTER (WHERE d.status = 'dead_letter' AND d.archived_at IS NULL)::int AS "deadLetter",
       COUNT(d.id) FILTER (WHERE d.status = 'acked' AND d.archived_at IS NULL)::int AS acked,
       COUNT(d.id) FILTER (WHERE d.archived_at IS NOT NULL)::int AS archived,
       COALESCE(MAX(d.attempt_count) FILTER (WHERE d.status IN ('pending', 'sent', 'retrying')), 0)::int AS "maxAttempts",
       MIN(d.created_at) FILTER (WHERE d.status IN ('pending', 'sent', 'retrying')
         AND d.replay_expires_at > $1) AS "oldestOutstandingAt",
       COUNT(d.id) FILTER (WHERE d.status = 'dead_letter'
         AND d.dead_lettered_at >= $1::timestamptz - interval '24 hours')::int AS "newDeadLetters24h"
     FROM agents a LEFT JOIN agent_connections c ON c.agent_id = a.id
     LEFT JOIN deliveries d ON d.recipient_agent_id = a.id
     GROUP BY a.id, c.id
     ORDER BY "expiredAwaitingSweep" DESC, "repeatedPolls" DESC,
       "oldestOutstandingAt" ASC NULLS LAST, a.id
     LIMIT 201`,
    [now],
  );
  return {
    observedAt: now.toISOString(),
    truncated: rows.length > 200,
    agents: rows.slice(0, 200).map((row) => {
      const {
        connectionId,
        tokenHash,
        webhookUrl,
        webhookSecretHash,
        participationRecord,
        ...metrics
      } = row;
      const connection = Object.assign(new AgentConnectionEntity(), {
        id: connectionId,
        tokenHash,
        webhookUrl,
        webhookSecretHash,
        transportMode: row.transportMode,
        continuousParticipation: participationRecord,
      });
      const continuousParticipation = participationSummary(connection, now);
      const pushAvailable =
        row.webhookConfigured &&
        row.status !== 'suspended' &&
        (!participationRecord ||
          (participationRecord.mode === 'webhook' &&
            continuousParticipation.enabled));
      return {
        ...metrics,
        continuousParticipation,
        outreach: {
          canPush: pushAvailable,
          channel: pushAvailable ? 'registered_webhook' : 'none',
          nextStep:
            row.status === 'suspended'
              ? 'resolve_suspension'
              : !row.transportMode
                ? 'connect_runtime'
                : row.repeatedPolls > 0
                  ? 'check_acknowledgement'
                  : pushAvailable
                    ? 'check_registered_webhook'
                    : 'host_authorized_return_schedule',
          limitation: pushAvailable
            ? 'Push reaches the registered runtime; it cannot start or fund a model.'
            : 'Inbox notifications cannot wake a polling runtime. An authorized host schedule or registered HTTPS webhook is required.',
        },
      };
    }),
  };
}
