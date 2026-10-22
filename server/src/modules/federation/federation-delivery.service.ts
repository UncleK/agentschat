import { randomUUID } from 'node:crypto';
import { enqueueDelivery } from '../../database/enqueue-delivery';
import { postWebhook } from './webhook-http';
import { recordAgentActivity } from './agent-activity';
import {
  Inject,
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { setTimeout as delay } from 'node:timers/promises';
import { In, Not, Repository } from 'typeorm';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';
import { deliveryRetentionMs } from '../../database/delivery-policy';
import { visibleMetadataSql } from '../moderation/content-visibility';
import {
  AgentStatus,
  ConnectionTransportMode,
  DeliveryChannel,
  DeliveryStatus,
  ThreadVisibility,
} from '../../database/domain.enums';
import { AgentConnectionEntity } from '../../database/entities/agent-connection.entity';
import { AgentEntity } from '../../database/entities/agent.entity';
import { DeliveryEntity } from '../../database/entities/delivery.entity';
import { EventEntity } from '../../database/entities/event.entity';
import { FederationCredentialsService } from './federation-credentials.service';
import { FederationHttpException } from './federation.errors';
import { AuthenticatedFederatedAgent } from './federation.types';

export interface PollResult {
  cursor: string | null;
  deliveries: Array<Record<string, unknown>>;
  pendingCount?: number;
  hasMore?: boolean;
  nextPollAfterSeconds?: number;
}

@Injectable()
export class FederationDeliveryService
  implements OnModuleInit, OnModuleDestroy
{
  private readonly logger = new Logger(FederationDeliveryService.name);
  private readonly activeDeliveryStatuses = [
    DeliveryStatus.Pending,
    DeliveryStatus.Sent,
    DeliveryStatus.Retrying,
  ];
  private readonly webhookRequestTimeoutMs: number;
  private isProcessingWebhooks = false;
  private readonly retryScheduleMs: number[];
  private readonly replayWindowMs: number;
  private readonly deliverySweepIntervalMs: number;
  private readonly presenceStaleAfterMs: number;
  private readonly presenceSweepIntervalMs: number;
  private deliverySweepTimer: NodeJS.Timeout | null = null;
  private presenceSweepTimer: NodeJS.Timeout | null = null;
  private isStopped = false;

  constructor(
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
    @InjectRepository(DeliveryEntity)
    private readonly deliveryRepository: Repository<DeliveryEntity>,
    @InjectRepository(AgentConnectionEntity)
    private readonly agentConnectionRepository: Repository<AgentConnectionEntity>,
    @InjectRepository(AgentEntity)
    private readonly agentRepository: Repository<AgentEntity>,
    @InjectRepository(EventEntity)
    private readonly eventRepository: Repository<EventEntity>,
    private readonly federationCredentialsService: FederationCredentialsService,
  ) {
    this.webhookRequestTimeoutMs =
      environment.nodeEnv === 'test' ? 200 : 10_000;
    this.retryScheduleMs =
      environment.nodeEnv === 'test' ? [0, 100, 200] : [0, 5_000, 30_000];
    this.replayWindowMs = deliveryRetentionMs(environment);
    this.deliverySweepIntervalMs = environment.nodeEnv === 'test' ? 50 : 1_000;
    this.presenceStaleAfterMs =
      Math.max(1, environment.presence.staleAfterSeconds) * 1_000;
    this.presenceSweepIntervalMs =
      Math.max(1, environment.presence.sweepIntervalSeconds) * 1_000;
  }

  onModuleInit(): void {
    this.isStopped = false;
    this.deliverySweepTimer = setInterval(() => {
      void this.processDueWebhookDeliveries();
    }, this.deliverySweepIntervalMs);
    this.deliverySweepTimer.unref();
    this.presenceSweepTimer = setInterval(() => {
      void this.sweepStaleAgentPresence().catch(() =>
        this.logger.warn('Presence sweep failed; it will retry.'),
      );
    }, this.presenceSweepIntervalMs);
    this.presenceSweepTimer.unref();
  }

  onModuleDestroy(): void {
    this.isStopped = true;
    if (this.deliverySweepTimer) {
      clearInterval(this.deliverySweepTimer);
      this.deliverySweepTimer = null;
    }
    if (this.presenceSweepTimer) {
      clearInterval(this.presenceSweepTimer);
      this.presenceSweepTimer = null;
    }
  }

  async enqueueEventForRecipient(
    event: EventEntity,
    recipientAgentId: string,
  ): Promise<DeliveryEntity> {
    const delivery = await enqueueDelivery(
      this.deliveryRepository.manager.connection,
      event.id,
      recipientAgentId,
      this.replayWindowMs,
    );
    this.poke();
    return delivery;
  }

  async bindPendingDeliveriesToConnection(
    recipientAgentId: string,
    connection: AgentConnectionEntity,
  ): Promise<void> {
    await this.deliveryRepository.update(
      { recipientAgentId, status: In(this.activeDeliveryStatuses) },
      {
        agentConnectionId: connection.id,
        deliveryChannel: connection.pollingEnabled
          ? DeliveryChannel.Polling
          : DeliveryChannel.Webhook,
      },
    );
    this.poke();
  }

  async pollDeliveries(
    agent: AuthenticatedFederatedAgent,
    cursor: string | undefined,
    limit: number | undefined,
    waitSeconds: number | undefined,
    signal?: AbortSignal,
    communityOnly = false,
  ): Promise<PollResult> {
    if (!agent.pollingEnabled) {
      throw new FederationHttpException(
        409,
        'polling_not_enabled',
        'Polling is not enabled for this agent connection.',
      );
    }

    const normalizedWaitSeconds = this.normalizeWaitSeconds(waitSeconds);
    const deadline = Date.now() + normalizedWaitSeconds * 1_000;
    const normalizedCursor = this.parseCursor(cursor);

    const leaseId = randomUUID();
    const db = this.deliveryRepository.manager.connection;
    await db.transaction(async (manager) => {
      await manager.query(
        'SELECT pg_advisory_xact_lock(hashtextextended($1, 0))',
        [`poll:${agent.id}`],
      );
      await manager.query(
        'DELETE FROM agent_poll_leases WHERE agent_id=$1 AND expires_at<=now()',
        [agent.id],
      );
      const rows = await manager.query<Array<{ count: string }>>(
        'SELECT count(*) FROM agent_poll_leases WHERE agent_id=$1',
        [agent.id],
      );
      if (Number(rows[0].count) >= 2)
        throw new FederationHttpException(
          429,
          'poll_concurrency_limit',
          'At most two concurrent polls per agent.',
        );
      await manager.query(
        'INSERT INTO agent_poll_leases(id,agent_id,expires_at) VALUES ($1,$2,$3)',
        [leaseId, agent.id, new Date(deadline + 5000)],
      );
    });
    try {
      await this.expireDueDeliveries(agent.id);
      while (!signal?.aborted && !this.isStopped) {
        const deliveries = await this.collectPollableDeliveries(
          agent.id,
          normalizedCursor,
          limit,
          communityOnly,
        );
        if (deliveries.length > 0 || Date.now() >= deadline) {
          if (!signal?.aborted)
            await this.recordAgentPollingActivity(agent, true);
          const pendingCount = communityOnly
            ? await this.outstandingQuery(agent.id, true)
                .andWhere('delivery.replayExpiresAt > :now', {
                  now: new Date(),
                })
                .getCount()
            : undefined;
          return {
            cursor:
              (deliveries.at(-1)?.cursor as string | undefined) ??
              (normalizedCursor === null ? null : String(normalizedCursor)),
            deliveries,
            pendingCount,
            hasMore:
              pendingCount === undefined
                ? undefined
                : pendingCount > deliveries.length,
            nextPollAfterSeconds: 5,
          };
        }
        try {
          await delay(
            Math.min(250, Math.max(1, deadline - Date.now())),
            undefined,
            { signal },
          );
        } catch (error) {
          if (!signal?.aborted) throw error;
        }
      }
      return {
        cursor: normalizedCursor === null ? null : String(normalizedCursor),
        deliveries: [],
      };
    } finally {
      await db.query('DELETE FROM agent_poll_leases WHERE id=$1', [leaseId]);
    }
  }

  async acknowledgeDeliveries(
    agent: AuthenticatedFederatedAgent,
    deliveryIds: string[],
  ) {
    if (
      !Array.isArray(deliveryIds) ||
      deliveryIds.length > 100 ||
      deliveryIds.some(
        (id) =>
          typeof id !== 'string' ||
          !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
            id.trim(),
          ),
      )
    ) {
      throw new FederationHttpException(
        400,
        'invalid_ack_batch',
        'ACK expects at most 100 UUID delivery IDs.',
      );
    }
    if (deliveryIds.length === 0) {
      throw new FederationHttpException(
        400,
        'acks_required',
        'At least one deliveryId is required.',
      );
    }

    const uniqueDeliveryIds = [
      ...new Set(deliveryIds.map((value) => value.trim()).filter(Boolean)),
    ];

    if (uniqueDeliveryIds.length === 0) {
      throw new FederationHttpException(
        400,
        'acks_required',
        'At least one deliveryId is required.',
      );
    }

    const deliveries = await this.deliveryRepository.findBy({
      recipientAgentId: agent.id,
      id: In(uniqueDeliveryIds),
    });
    const deliveriesById = new Map(
      deliveries.map((delivery) => [delivery.id, delivery]),
    );
    const results: Array<Record<string, unknown>> = [];

    for (const deliveryId of uniqueDeliveryIds) {
      const delivery = deliveriesById.get(deliveryId);

      if (!delivery) {
        results.push({
          deliveryId,
          status: 'not_found',
        });
        continue;
      }

      if (delivery.status === DeliveryStatus.Acked) {
        results.push({
          deliveryId,
          status: 'already_acked',
        });
        continue;
      }

      const acknowledged = await this.deliveryRepository.update(
        {
          id: delivery.id,
          recipientAgentId: agent.id,
          status: Not(DeliveryStatus.Acked),
        },
        {
          status: DeliveryStatus.Acked,
          ackedAt: new Date(),
          nextAttemptAt: null,
          lastError: null,
          deadLetteredAt: null,
        },
      );

      results.push({
        deliveryId,
        status: acknowledged.affected ? 'acked' : 'already_acked',
      });
    }

    await this.recordAgentPollingActivity(agent, true);
    this.poke();

    return {
      results,
    };
  }

  poke(): void {
    if (this.isStopped) {
      return;
    }

    setImmediate(() => {
      void this.processDueWebhookDeliveries();
    });
  }

  async sweepStaleAgentPresence(
    referenceTime = new Date(),
  ): Promise<{ offlineAgentIds: string[] }> {
    if (this.isStopped) {
      return {
        offlineAgentIds: [],
      };
    }

    const referenceTimeMs = referenceTime.getTime();
    const connections = await this.agentConnectionRepository.find({
      relations: {
        agent: true,
      },
    });

    const offlineAgentIds = [
      ...new Set(
        connections
          .filter((connection) =>
            this.shouldMarkAgentOffline(connection, referenceTimeMs),
          )
          .map((connection) => connection.agentId),
      ),
    ];

    if (offlineAgentIds.length === 0) {
      return {
        offlineAgentIds: [],
      };
    }

    await this.agentRepository.update(
      {
        id: In(offlineAgentIds),
      },
      {
        status: AgentStatus.Offline,
      },
    );

    return {
      offlineAgentIds,
    };
  }

  private async collectPollableDeliveries(
    recipientAgentId: string,
    _cursor: number | null,
    limit: number | undefined,
    communityOnly = false,
  ): Promise<Array<Record<string, unknown>>> {
    const boundedLimit = limit ?? 1;
    if (
      !Number.isInteger(boundedLimit) ||
      boundedLimit < 1 ||
      boundedLimit > 50
    )
      throw new FederationHttpException(
        400,
        'invalid_limit',
        'limit must be an integer from 1 to 50.',
      );
    const deliveries: Array<Record<string, unknown>> = [];
    const outstandingBatch = await this.outstandingQuery(
      recipientAgentId,
      communityOnly,
    )
      .andWhere('delivery.replayExpiresAt > :now', { now: new Date() })
      .take(boundedLimit)
      .getMany();
    for (const outstanding of outstandingBatch) {
      if (!(await this.ensureDeliveryIsActive(outstanding))) {
        continue;
      }

      if (
        outstanding.nextAttemptAt &&
        outstanding.nextAttemptAt.getTime() > Date.now()
      ) {
        break;
      }

      const claimed = await this.claimDeliveryAttempt(
        outstanding,
        DeliveryChannel.Polling,
        this.nextAttemptAt(outstanding.attemptCount + 1),
      );
      if (!claimed) continue;
      deliveries.push(await this.serializeDeliveryById(claimed.id));
    }

    return deliveries;
  }

  private async recordAgentPollingActivity(
    agent: AuthenticatedFederatedAgent,
    heartbeat: boolean,
  ): Promise<void> {
    await recordAgentActivity(
      this.agentRepository,
      this.agentConnectionRepository,
      agent,
      heartbeat,
    );
  }

  private async processDueWebhookDeliveries(): Promise<void> {
    if (this.isStopped || this.isProcessingWebhooks) return;
    this.isProcessingWebhooks = true;
    try {
      await this.expireDueDeliveries();
      const connections = await this.agentConnectionRepository.find({
        where: {
          transportMode: In([
            ConnectionTransportMode.Webhook,
            ConnectionTransportMode.Hybrid,
          ]),
        },
        order: { updatedAt: 'ASC' },
      });

      const deliver = async (connection: AgentConnectionEntity) => {
        if (
          (connection.webhookBlockedUntil &&
            connection.webhookBlockedUntil.getTime() > Date.now()) ||
          !connection.webhookUrl ||
          !connection.webhookSecret ||
          (connection.transportMode !== ConnectionTransportMode.Webhook &&
            connection.transportMode !== ConnectionTransportMode.Hybrid)
        ) {
          return;
        }

        const outstanding = await this.loadEarliestOutstandingDelivery(
          connection.agentId,
          false,
          true,
        );

        if (!outstanding) {
          return;
        }

        if (!(await this.ensureDeliveryIsActive(outstanding))) {
          return;
        }

        if (
          outstanding.nextAttemptAt &&
          outstanding.nextAttemptAt.getTime() > Date.now()
        ) {
          return;
        }

        const claimed = await this.claimDeliveryAttempt(
          outstanding,
          DeliveryChannel.Webhook,
          new Date(Date.now() + this.webhookRequestTimeoutMs + 1_000),
        );
        if (!claimed) return;

        const payload = await this.serializeDeliveryById(outstanding.id);
        const body = JSON.stringify({
          delivery: payload,
        });
        const timestamp = new Date().toISOString();
        const signature = this.federationCredentialsService.signWebhookPayload(
          connection.webhookSecret,
          timestamp,
          body,
        );

        const timeoutSignal = AbortSignal.timeout(this.webhookRequestTimeoutMs);
        try {
          const response = await postWebhook(
            connection.webhookUrl,
            body,
            {
              'content-type': 'application/json',
              'x-agents-chat-delivery-id': outstanding.id,
              'x-agents-chat-timestamp': timestamp,
              'x-agents-chat-signature': signature,
            },
            timeoutSignal,
          );

          if (!response.ok) {
            await this.recordWebhookFailure(connection.id);
            await this.markDeliveryAttemptFailure(
              claimed,
              `Webhook returned HTTP ${response.status}.`,
              connection.pollingEnabled,
            );
            return;
          }

          await this.agentConnectionRepository.update(connection.id, {
            webhookConsecutiveFailures: 0,
            webhookBlockedUntil: null,
          });
          // ACK is terminal even when it arrived before the HTTP response.
          const exhaustedWithoutFallback =
            !connection.pollingEnabled &&
            claimed.webhookAttemptCount >= this.retryScheduleMs.length;
          await this.deliveryRepository.update(
            {
              id: claimed.id,
              status: In(this.activeDeliveryStatuses),
              attemptCount: claimed.attemptCount,
            },
            {
              lastError: exhaustedWithoutFallback
                ? 'Webhook retry budget exhausted before acknowledgement.'
                : null,
              ...(exhaustedWithoutFallback
                ? {
                    status: DeliveryStatus.DeadLetter,
                    deadLetteredAt: new Date(),
                  }
                : {}),
              nextAttemptAt:
                claimed.webhookAttemptCount >= this.retryScheduleMs.length
                  ? null
                  : this.nextAttemptAt(claimed.webhookAttemptCount),
            },
          );
        } catch (error) {
          const message =
            timeoutSignal.aborted ||
            (error instanceof Error &&
              ['TimeoutError', 'AbortError'].includes(error.name))
              ? 'Webhook request timed out.'
              : 'Webhook delivery failed.';
          await this.recordWebhookFailure(connection.id);
          await this.markDeliveryAttemptFailure(
            claimed,
            message,
            connection.pollingEnabled,
          );
        }
      };
      let next = 0;
      await Promise.all(
        Array.from({ length: Math.min(4, connections.length) }, async () => {
          while (next < connections.length && !this.isStopped) {
            const connection = connections[next++];
            await deliver(connection);
          }
        }),
      );
    } catch (error) {
      if (
        this.isStopped ||
        (error instanceof Error && /connection terminated/i.test(error.message))
      ) {
        return;
      }

      this.logger.warn('Webhook delivery sweep failed; it will retry.');
    } finally {
      this.isProcessingWebhooks = false;
    }
  }

  private async recordWebhookFailure(connectionId: string): Promise<void> {
    await this.agentConnectionRepository
      .createQueryBuilder()
      .update()
      .set({
        webhookConsecutiveFailures: () => 'webhook_consecutive_failures + 1',
        webhookBlockedUntil: () =>
          "CASE WHEN webhook_consecutive_failures >= 2 THEN now() + interval '30 seconds' ELSE webhook_blocked_until END",
      })
      .where('id = :id', { id: connectionId })
      .execute();
  }

  private async claimDeliveryAttempt(
    delivery: DeliveryEntity,
    channel: DeliveryChannel,
    nextAttemptAt: Date,
  ): Promise<DeliveryEntity | null> {
    const next = {
      attemptCount: delivery.attemptCount + 1,
      ...(channel === DeliveryChannel.Webhook
        ? { webhookAttemptCount: delivery.webhookAttemptCount + 1 }
        : {}),
      deliveryChannel: channel,
      lastAttemptAt: new Date(),
      status:
        delivery.attemptCount === 0
          ? DeliveryStatus.Sent
          : DeliveryStatus.Retrying,
      nextAttemptAt,
    };
    const claimed = await this.deliveryRepository.update(
      {
        id: delivery.id,
        status: In(this.activeDeliveryStatuses),
        attemptCount: delivery.attemptCount,
      },
      next,
    );
    return claimed.affected ? Object.assign(delivery, next) : null;
  }

  private async markDeliveryAttemptFailure(
    delivery: DeliveryEntity,
    message: string,
    pollingEnabled: boolean,
  ): Promise<void> {
    const expired = delivery.replayExpiresAt.getTime() <= Date.now();
    const pushExhausted =
      delivery.webhookAttemptCount >= this.retryScheduleMs.length;
    const deadLettered = expired || (pushExhausted && !pollingEnabled);
    await this.deliveryRepository.update(
      {
        id: delivery.id,
        status: In(this.activeDeliveryStatuses),
        attemptCount: delivery.attemptCount,
      },
      {
        lastError: message,
        status: deadLettered
          ? DeliveryStatus.DeadLetter
          : DeliveryStatus.Retrying,
        deadLetteredAt: deadLettered ? new Date() : null,
        nextAttemptAt:
          expired || pushExhausted
            ? null
            : this.nextAttemptAt(delivery.webhookAttemptCount),
      },
    );
  }

  private async ensureDeliveryIsActive(
    delivery: DeliveryEntity,
  ): Promise<boolean> {
    if (
      delivery.status === DeliveryStatus.Acked ||
      delivery.status === DeliveryStatus.DeadLetter
    ) {
      return false;
    }

    if (delivery.replayExpiresAt.getTime() <= Date.now()) {
      await this.deliveryRepository.update(
        {
          id: delivery.id,
          status: In(this.activeDeliveryStatuses),
          attemptCount: delivery.attemptCount,
        },
        {
          status: DeliveryStatus.DeadLetter,
          deadLetteredAt: new Date(),
          nextAttemptAt: null,
          lastError:
            'Delivery retention window expired before acknowledgement.',
        },
      );
      return false;
    }

    return true;
  }

  private async loadEarliestOutstandingDelivery(
    recipientAgentId: string,
    communityOnly = false,
    forWebhook = false,
  ): Promise<DeliveryEntity | null> {
    const query = this.outstandingQuery(recipientAgentId, communityOnly);
    if (forWebhook)
      query.andWhere('delivery.webhookAttemptCount < :maxAttempts', {
        maxAttempts: this.retryScheduleMs.length,
      });
    return query.take(1).getOne();
  }

  private outstandingQuery(recipientAgentId: string, communityOnly = false) {
    const query = this.deliveryRepository
      .createQueryBuilder('delivery')
      .where(
        'delivery.recipientAgentId = :id AND delivery.status IN (:...statuses)',
        {
          id: recipientAgentId,
          statuses: this.activeDeliveryStatuses,
        },
      );
    if (communityOnly)
      query
        .innerJoin('delivery.event', 'event')
        .innerJoin('event.thread', 'thread')
        .andWhere(
          "(event.eventType LIKE 'forum.%' OR event.eventType LIKE 'debate.%')",
        )
        .andWhere('thread.visibility = :visibility', {
          visibility: ThreadVisibility.Public,
        })
        .andWhere(visibleMetadataSql('event.metadata'))
        .andWhere(visibleMetadataSql('thread.metadata'));
    return query.orderBy('delivery.sequence', 'ASC');
  }

  private async expireDueDeliveries(recipientAgentId?: string) {
    const query = this.deliveryRepository
      .createQueryBuilder()
      .update(DeliveryEntity)
      .set({
        status: DeliveryStatus.DeadLetter,
        deadLetteredAt: new Date(),
        nextAttemptAt: null,
        lastError: 'Delivery retention window expired before acknowledgement.',
      })
      .where('status IN (:...statuses)', {
        statuses: this.activeDeliveryStatuses,
      })
      .andWhere('replay_expires_at <= :now', { now: new Date() });
    if (recipientAgentId)
      query.andWhere('recipient_agent_id = :recipientAgentId', {
        recipientAgentId,
      });
    await query.execute();
  }

  private async serializeDeliveryById(
    deliveryId: string,
  ): Promise<Record<string, unknown>> {
    const delivery = await this.deliveryRepository.findOneBy({
      id: deliveryId,
    });

    if (!delivery) {
      throw new FederationHttpException(
        404,
        'delivery_not_found',
        `Delivery ${deliveryId} was not found.`,
      );
    }

    const event = await this.eventRepository.findOneBy({
      id: delivery.eventId,
    });

    if (!event) {
      throw new FederationHttpException(
        404,
        'event_not_found',
        `Event ${delivery.eventId} was not found for delivery ${delivery.id}.`,
      );
    }

    return {
      deliveryId: delivery.id,
      cursor: String(delivery.sequence),
      sequence: delivery.sequence,
      status: delivery.status,
      channel: delivery.deliveryChannel,
      expiresAt: delivery.replayExpiresAt.toISOString(),
      attemptCount: delivery.attemptCount,
      webhookAttemptCount: delivery.webhookAttemptCount,
      event: {
        id: event.id,
        type: this.externalEventType(delivery, event),
        threadId: event.threadId,
        actorType: event.actorType,
        actorAgentId: event.actorAgentId,
        actorUserId: event.actorUserId,
        targetType: event.targetType,
        targetId: event.targetId,
        contentType: event.contentType,
        content: event.content,
        metadata: event.metadata,
        parentEventId: event.parentEventId,
        occurredAt: event.occurredAt.toISOString(),
      },
    };
  }

  private externalEventType(
    delivery: DeliveryEntity,
    event: EventEntity,
  ): string {
    if (
      event.eventType === 'dm.send' &&
      event.actorAgentId !== delivery.recipientAgentId
    ) {
      return 'dm.received';
    }

    return event.eventType;
  }

  private nextAttemptAt(attemptCount: number): Date {
    const delayMs =
      this.retryScheduleMs[
        Math.min(attemptCount, this.retryScheduleMs.length - 1)
      ] ?? 0;
    return new Date(Date.now() + delayMs);
  }

  private parseCursor(cursor: string | undefined): number | null {
    if (!cursor?.trim()) {
      return null;
    }

    const parsed = Number.parseInt(cursor, 10);

    if (Number.isNaN(parsed) || parsed < 0) {
      throw new FederationHttpException(
        400,
        'invalid_cursor',
        'cursor must be a positive integer.',
      );
    }

    return parsed;
  }

  private normalizeWaitSeconds(waitSeconds: number | undefined): number {
    if (waitSeconds === undefined || Number.isNaN(waitSeconds)) {
      return 0;
    }

    return Math.max(0, Math.min(waitSeconds, 5));
  }

  private shouldMarkAgentOffline(
    connection: AgentConnectionEntity,
    referenceTimeMs: number,
  ): boolean {
    const agent = connection.agent;

    if (
      !agent ||
      (agent.status !== AgentStatus.Online &&
        agent.status !== AgentStatus.Debating)
    ) {
      return false;
    }

    const lastPresenceAt =
      connection.lastHeartbeatAt ?? connection.lastSeenAt ?? agent.lastSeenAt;

    if (!lastPresenceAt) {
      return false;
    }

    return (
      referenceTimeMs - lastPresenceAt.getTime() >= this.presenceStaleAfterMs
    );
  }
}
