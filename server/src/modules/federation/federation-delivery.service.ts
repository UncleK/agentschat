import {
  Inject,
  Injectable,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { setTimeout as delay } from 'node:timers/promises';
import { Repository } from 'typeorm';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';
import {
  ConnectionTransportMode,
  DeliveryChannel,
  DeliveryStatus,
} from '../../database/domain.enums';
import { AgentConnectionEntity } from '../../database/entities/agent-connection.entity';
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
  private readonly retryScheduleMs: number[];
  private readonly replayWindowMs: number;
  private readonly sweepIntervalMs: number;
  private sweepTimer: NodeJS.Timeout | null = null;
  private isStopped = false;

  constructor(
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
    @InjectRepository(DeliveryEntity)
    private readonly deliveryRepository: Repository<DeliveryEntity>,
    @InjectRepository(AgentConnectionEntity)
    private readonly agentConnectionRepository: Repository<AgentConnectionEntity>,
    @InjectRepository(EventEntity)
    private readonly eventRepository: Repository<EventEntity>,
    private readonly federationCredentialsService: FederationCredentialsService,
  ) {
    this.retryScheduleMs =
      environment.nodeEnv === 'test' ? [0, 100, 200] : [0, 5_000, 30_000];
    this.replayWindowMs = environment.nodeEnv === 'test' ? 800 : 15 * 60 * 1000;
    this.sweepIntervalMs = environment.nodeEnv === 'test' ? 50 : 1_000;
  }

  onModuleInit(): void {
    this.isStopped = false;
    this.sweepTimer = setInterval(() => {
      void this.processDueWebhookDeliveries();
    }, this.sweepIntervalMs);
    this.sweepTimer.unref();
  }

  onModuleDestroy(): void {
    this.isStopped = true;
    if (this.sweepTimer) {
      clearInterval(this.sweepTimer);
      this.sweepTimer = null;
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
    const deliveries = await this.deliveryRepository.findBy({
      recipientAgentId,
    });

    const pendingDeliveries = deliveries.filter(
      (delivery) =>
        delivery.status !== DeliveryStatus.Acked &&
        delivery.status !== DeliveryStatus.DeadLetter,
    );

    if (pendingDeliveries.length === 0) {
      return;
    }

    for (const delivery of pendingDeliveries) {
      delivery.agentConnectionId = connection.id;
      delivery.deliveryChannel = connection.pollingEnabled
        ? DeliveryChannel.Polling
        : DeliveryChannel.Webhook;
    }

    await this.deliveryRepository.save(pendingDeliveries);
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

      delivery.status = DeliveryStatus.Acked;
      delivery.ackedAt = new Date();
      delivery.nextAttemptAt = null;
      delivery.lastError = null;
      await this.deliveryRepository.save(delivery);

      results.push({
        deliveryId,
        status: 'acked',
      });
    }

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

      const attemptNumber = outstanding.attemptCount;
      outstanding.attemptCount += 1;
      outstanding.deliveryChannel = DeliveryChannel.Polling;
      outstanding.lastAttemptAt = new Date();
      outstanding.status =
        attemptNumber === 0 ? DeliveryStatus.Sent : DeliveryStatus.Retrying;
      outstanding.nextAttemptAt = this.nextAttemptAt(outstanding.attemptCount);

      const savedDelivery = await this.deliveryRepository.save(outstanding);
      deliveries.push(await this.serializeDeliveryById(savedDelivery.id));
      break;
    }

    return deliveries;
  }

  private async processDueWebhookDeliveries(): Promise<void> {
    if (this.isStopped) {
      return;
    }

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
          });

          if (!response.ok) {
            await this.markDeliveryAttemptFailure(
              outstanding,
              `Webhook returned HTTP ${response.status}.`,
            );
            continue;
          }

          const attemptNumber = outstanding.attemptCount;
          outstanding.attemptCount += 1;
          outstanding.deliveryChannel = DeliveryChannel.Webhook;
          outstanding.lastAttemptAt = new Date();
          outstanding.status =
            attemptNumber === 0 ? DeliveryStatus.Sent : DeliveryStatus.Retrying;
          outstanding.lastError = null;
          outstanding.nextAttemptAt = this.nextAttemptAt(
            outstanding.attemptCount,
          );
          await this.deliveryRepository.save(outstanding);
        } catch (error) {
          const message =
            error instanceof Error ? error.message : 'Webhook delivery failed.';
          await this.markDeliveryAttemptFailure(outstanding, message);
        }
      }
    } catch (error) {
      if (
        this.isStopped ||
        (error instanceof Error && /connection terminated/i.test(error.message))
      ) {
        return;
      }

      throw error;
    }
  }

  private async markDeliveryAttemptFailure(
    delivery: DeliveryEntity,
    message: string,
  ): Promise<void> {
    delivery.attemptCount += 1;
    delivery.lastAttemptAt = new Date();
    delivery.lastError = message;

    if (
      delivery.attemptCount >= this.retryScheduleMs.length ||
      delivery.replayExpiresAt.getTime() <= Date.now()
    ) {
      delivery.status = DeliveryStatus.DeadLetter;
      delivery.deadLetteredAt = new Date();
      delivery.nextAttemptAt = null;
      await this.deliveryRepository.save(delivery);
      return;
    }

    delivery.status = DeliveryStatus.Retrying;
    delivery.nextAttemptAt = this.nextAttemptAt(delivery.attemptCount);
    await this.deliveryRepository.save(delivery);
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
      delivery.status = DeliveryStatus.DeadLetter;
      delivery.deadLetteredAt = new Date();
      delivery.nextAttemptAt = null;
      await this.deliveryRepository.save(delivery);
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
}
