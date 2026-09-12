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
import {
  AgentStatus,
  ConnectionTransportMode,
  DeliveryChannel,
  DeliveryStatus,
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
    this.replayWindowMs = environment.nodeEnv === 'test' ? 800 : 15 * 60 * 1000;
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
    const connection = await this.agentConnectionRepository.findOneBy({
      agentId: recipientAgentId,
    });
    const sequence = await this.nextSequenceForRecipient(recipientAgentId);
    const delivery = await this.deliveryRepository.save(
      this.deliveryRepository.create({
        eventId: event.id,
        recipientAgentId,
        agentConnectionId: connection?.id ?? null,
        sequence,
        deliveryChannel: connection?.pollingEnabled
          ? DeliveryChannel.Polling
          : DeliveryChannel.Webhook,
        nextAttemptAt: new Date(),
        replayExpiresAt: new Date(Date.now() + this.replayWindowMs),
      }),
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

    while (true) {
      const deliveries = await this.collectPollableDeliveries(
        agent.id,
        normalizedCursor,
        limit,
      );

      if (deliveries.length > 0 || Date.now() >= deadline) {
        await this.recordAgentPollingActivity(agent, true);
        const latestCursor = deliveries.at(-1)?.cursor as string | undefined;

        return {
          cursor:
            latestCursor ??
            (normalizedCursor === null ? null : String(normalizedCursor)),
          deliveries,
        };
      }

      await delay(50);
    }
  }

  async acknowledgeDeliveries(
    agent: AuthenticatedFederatedAgent,
    deliveryIds: string[],
  ) {
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
  ): Promise<Array<Record<string, unknown>>> {
    const boundedLimit = Math.max(1, Math.min(limit ?? 1, 1));
    const deliveries: Array<Record<string, unknown>> = [];

    while (deliveries.length < boundedLimit) {
      const outstanding =
        await this.loadEarliestOutstandingDelivery(recipientAgentId);

      if (!outstanding) {
        break;
      }

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
      break;
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
      const connections = await this.agentConnectionRepository.find({
        where: {},
        order: { createdAt: 'ASC' },
      });

      for (const connection of connections) {
        if (
          !connection.webhookUrl ||
          !connection.webhookSecret ||
          (connection.transportMode !== ConnectionTransportMode.Webhook &&
            connection.transportMode !== ConnectionTransportMode.Hybrid)
        ) {
          continue;
        }

        const outstanding = await this.loadEarliestOutstandingDelivery(
          connection.agentId,
        );

        if (!outstanding) {
          continue;
        }

        if (!(await this.ensureDeliveryIsActive(outstanding))) {
          continue;
        }

        if (
          outstanding.nextAttemptAt &&
          outstanding.nextAttemptAt.getTime() > Date.now()
        ) {
          continue;
        }

        const claimed = await this.claimDeliveryAttempt(
          outstanding,
          DeliveryChannel.Webhook,
          new Date(Date.now() + this.webhookRequestTimeoutMs + 1_000),
        );
        if (!claimed) continue;

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
          const response = await fetch(connection.webhookUrl, {
            method: 'POST',
            headers: {
              'content-type': 'application/json',
              'x-agents-chat-delivery-id': outstanding.id,
              'x-agents-chat-timestamp': timestamp,
              'x-agents-chat-signature': signature,
            },
            body,
            signal: timeoutSignal,
          });
          void response.body?.cancel().catch(() => undefined);

          if (!response.ok) {
            await this.markDeliveryAttemptFailure(
              claimed,
              `Webhook returned HTTP ${response.status}.`,
            );
            continue;
          }

          // ACK is terminal even when it arrived before the HTTP response.
          await this.deliveryRepository.update(
            {
              id: claimed.id,
              status: In(this.activeDeliveryStatuses),
              attemptCount: claimed.attemptCount,
            },
            {
              lastError: null,
              nextAttemptAt: this.nextAttemptAt(claimed.attemptCount),
            },
          );
        } catch (error) {
          const message =
            timeoutSignal.aborted ||
            (error instanceof Error &&
              ['TimeoutError', 'AbortError'].includes(error.name))
              ? 'Webhook request timed out.'
              : 'Webhook delivery failed.';
          await this.markDeliveryAttemptFailure(claimed, message);
        }
      }
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

  private async claimDeliveryAttempt(
    delivery: DeliveryEntity,
    channel: DeliveryChannel,
    nextAttemptAt: Date,
  ): Promise<DeliveryEntity | null> {
    const next = {
      attemptCount: delivery.attemptCount + 1,
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
  ): Promise<void> {
    const expired =
      delivery.attemptCount >= this.retryScheduleMs.length ||
      delivery.replayExpiresAt.getTime() <= Date.now();
    await this.deliveryRepository.update(
      {
        id: delivery.id,
        status: In(this.activeDeliveryStatuses),
        attemptCount: delivery.attemptCount,
      },
      {
        lastError: message,
        status: expired ? DeliveryStatus.DeadLetter : DeliveryStatus.Retrying,
        deadLetteredAt: expired ? new Date() : null,
        nextAttemptAt: expired
          ? null
          : this.nextAttemptAt(delivery.attemptCount),
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

    if (
      delivery.replayExpiresAt.getTime() <= Date.now() ||
      delivery.attemptCount >= this.retryScheduleMs.length
    ) {
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
        },
      );
      return false;
    }

    return true;
  }

  private async loadEarliestOutstandingDelivery(
    recipientAgentId: string,
  ): Promise<DeliveryEntity | null> {
    const deliveries = await this.deliveryRepository.find({
      where: { recipientAgentId },
      order: {
        sequence: 'ASC',
      },
    });

    return (
      deliveries.find(
        (delivery) =>
          delivery.status !== DeliveryStatus.Acked &&
          delivery.status !== DeliveryStatus.DeadLetter,
      ) ?? null
    );
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

  private async nextSequenceForRecipient(
    recipientAgentId: string,
  ): Promise<number> {
    const deliveries = await this.deliveryRepository.find({
      where: { recipientAgentId },
      order: { sequence: 'DESC' },
      take: 1,
    });

    return (deliveries[0]?.sequence ?? 0) + 1;
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
