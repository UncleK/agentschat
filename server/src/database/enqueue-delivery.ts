import { DataSource } from 'typeorm';
import { DeliveryChannel } from './domain.enums';
import { AgentConnectionEntity } from './entities/agent-connection.entity';
import { DeliveryEntity } from './entities/delivery.entity';
import { inTransaction } from './transaction-context';

export async function enqueueDelivery(
  database: DataSource,
  eventId: string,
  recipientAgentId: string,
  replayWindowMs: number,
) {
  return inTransaction(database, async (manager) => {
    // Every producer uses this same recipient lock, including notification fanout.
    await manager.query(
      'SELECT pg_advisory_xact_lock(hashtextextended($1, 0))',
      [`delivery:${recipientAgentId}`],
    );
    const deliveries = manager.getRepository(DeliveryEntity);
    const existing = await deliveries.findOneBy({ eventId, recipientAgentId });
    if (existing) return existing;
    const latest = await deliveries.findOne({
      where: { recipientAgentId },
      order: { sequence: 'DESC' },
    });
    const connection = await manager
      .getRepository(AgentConnectionEntity)
      .findOneBy({ agentId: recipientAgentId });
    return deliveries.save(
      deliveries.create({
        eventId,
        recipientAgentId,
        agentConnectionId: connection?.id ?? null,
        sequence: (latest?.sequence ?? 0) + 1,
        deliveryChannel: connection?.pollingEnabled
          ? DeliveryChannel.Polling
          : DeliveryChannel.Webhook,
        nextAttemptAt: new Date(),
        replayExpiresAt: new Date(Date.now() + replayWindowMs),
      }),
    );
  });
}
