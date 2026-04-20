import { createServer } from 'node:http';
import { AddressInfo } from 'node:net';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { Repository } from 'typeorm';
import {
  AgentStatus,
  AgentDmAcceptanceMode,
  DeliveryStatus,
} from '../../src/database/domain.enums';
import { AgentConnectionEntity } from '../../src/database/entities/agent-connection.entity';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { DeliveryEntity } from '../../src/database/entities/delivery.entity';
import { EventEntity } from '../../src/database/entities/event.entity';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import { FederationDeliveryService } from '../../src/modules/federation/federation-delivery.service';
import { PolicyService } from '../../src/modules/policy/policy.service';
import {
  TestApplicationContext,
  createTestApplication,
  typedValue,
} from '../support/test-app';
import {
  claimFederatedAgent,
  importSelfAgent,
  waitForActionStatus,
} from './support/federation-test-support';

interface AcceptedActionBody {
  id: string;
}

interface DeliveryPollBody {
  cursor: string | null;
  deliveries: Array<{
    deliveryId: string;
    event: {
      type: string;
      content: string;
    };
  }>;
}

interface AckBody {
  results: Array<{
    status: string;
  }>;
}

describe('Federation delivery (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let federationCredentialsService: FederationCredentialsService;
  let federationDeliveryService: FederationDeliveryService;
  let policyService: PolicyService;
  let agentRepository: Repository<AgentEntity>;
  let agentConnectionRepository: Repository<AgentConnectionEntity>;
  let deliveryRepository: Repository<DeliveryEntity>;
  let eventRepository: Repository<EventEntity>;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    federationCredentialsService = app.get(FederationCredentialsService);
    federationDeliveryService = app.get(FederationDeliveryService);
    policyService = app.get(PolicyService);
    agentRepository = context.dataSource.getRepository(AgentEntity);
    agentConnectionRepository = context.dataSource.getRepository(
      AgentConnectionEntity,
    );
    deliveryRepository = context.dataSource.getRepository(DeliveryEntity);
    eventRepository = context.dataSource.getRepository(EventEntity);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('supports cursor polling, explicit ACKs, and per-recipient ordering', async () => {
    const sender = await importSelfAgent(
      app,
      'delivery-poll-sender',
      'Delivery Poll Sender',
    );
    const recipient = await importSelfAgent(
      app,
      'delivery-poll-recipient',
      'Delivery Poll Recipient',
    );
    await policyService.upsertAgentSafetyPolicy(recipient.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    const senderClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      sender.id,
      {
        pollingEnabled: true,
      },
    );
    const recipientClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      recipient.id,
      {
        pollingEnabled: true,
      },
    );

    const firstAction = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${senderClaim.accessToken}`)
      .set('Idempotency-Key', 'delivery-poll-1')
      .send({
        type: 'dm.send',
        payload: {
          targetType: 'agent',
          targetId: recipient.id,
          content: 'First message',
        },
      })
      .expect(202);
    const secondAction = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${senderClaim.accessToken}`)
      .set('Idempotency-Key', 'delivery-poll-2')
      .send({
        type: 'dm.send',
        payload: {
          targetType: 'agent',
          targetId: recipient.id,
          content: 'Second message',
        },
      })
      .expect(202);
    const firstActionBody = typedValue<AcceptedActionBody>(firstAction.body);
    const secondActionBody = typedValue<AcceptedActionBody>(secondAction.body);

    await waitForActionStatus(app, senderClaim.accessToken, firstActionBody.id);
    await waitForActionStatus(
      app,
      senderClaim.accessToken,
      secondActionBody.id,
    );

    const firstPoll = await request(app.getHttpServer())
      .get('/api/v1/deliveries/poll?wait_seconds=1')
      .set('Authorization', `Bearer ${recipientClaim.accessToken}`)
      .expect(200);
    const firstPollBody = typedValue<DeliveryPollBody>(firstPoll.body);

    expect(firstPollBody.deliveries).toHaveLength(1);
    expect(firstPollBody.deliveries[0]?.event.type).toBe('dm.received');
    expect(firstPollBody.deliveries[0]?.event.content).toBe('First message');

    const repeatedFirstPoll = await request(app.getHttpServer())
      .get(
        `/api/v1/deliveries/poll?cursor=${firstPollBody.cursor}&wait_seconds=1`,
      )
      .set('Authorization', `Bearer ${recipientClaim.accessToken}`)
      .expect(200);
    const repeatedFirstPollBody = typedValue<DeliveryPollBody>(
      repeatedFirstPoll.body,
    );

    expect(repeatedFirstPollBody.deliveries).toHaveLength(1);
    expect(repeatedFirstPollBody.deliveries[0]?.deliveryId).toBe(
      firstPollBody.deliveries[0]?.deliveryId,
    );

    await request(app.getHttpServer())
      .post('/api/v1/acks')
      .set('Authorization', `Bearer ${recipientClaim.accessToken}`)
      .send({
        deliveryIds: [firstPollBody.deliveries[0]?.deliveryId],
      })
      .expect(201)
      .expect(({ body }: { body: AckBody }) => {
        expect(body.results[0].status).toBe('acked');
      });

    const secondPoll = await request(app.getHttpServer())
      .get(
        `/api/v1/deliveries/poll?cursor=${firstPollBody.cursor}&wait_seconds=1`,
      )
      .set('Authorization', `Bearer ${recipientClaim.accessToken}`)
      .expect(200);
    const secondPollBody = typedValue<DeliveryPollBody>(secondPoll.body);

    expect(secondPollBody.deliveries).toHaveLength(1);
    expect(secondPollBody.deliveries[0]?.event.content).toBe('Second message');

    await request(app.getHttpServer())
      .post('/api/v1/acks')
      .set('Authorization', `Bearer ${recipientClaim.accessToken}`)
      .send({
        deliveryIds: [secondPollBody.deliveries[0]?.deliveryId],
      })
      .expect(201);

    const emptyPoll = await request(app.getHttpServer())
      .get(
        `/api/v1/deliveries/poll?cursor=${secondPollBody.cursor}&wait_seconds=0`,
      )
      .set('Authorization', `Bearer ${recipientClaim.accessToken}`)
      .expect(200);
    const emptyPollBody = typedValue<DeliveryPollBody>(emptyPoll.body);

    expect(emptyPollBody.deliveries).toEqual([]);
  });

  it('marks stale agent presence offline and restores online status on the next poll', async () => {
    const agent = await importSelfAgent(
      app,
      'delivery-presence-agent',
      'Delivery Presence Agent',
    );
    const claim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      agent.id,
      {
        pollingEnabled: true,
      },
    );

    const staleAt = new Date(Date.now() - 10 * 60 * 1000);

    await agentConnectionRepository.update(
      { agentId: agent.id },
      {
        lastHeartbeatAt: staleAt,
        lastSeenAt: staleAt,
      },
    );
    await agentRepository.update(
      { id: agent.id },
      {
        status: AgentStatus.Online,
        lastSeenAt: staleAt,
      },
    );

    const sweepResult = await federationDeliveryService.sweepStaleAgentPresence(
      new Date(),
    );

    expect(sweepResult.offlineAgentIds).toContain(agent.id);
    await expect(
      agentRepository.findOneByOrFail({ id: agent.id }),
    ).resolves.toMatchObject({
      status: AgentStatus.Offline,
    });

    await request(app.getHttpServer())
      .get('/api/v1/deliveries/poll?wait_seconds=0')
      .set('Authorization', `Bearer ${claim.accessToken}`)
      .expect(200)
      .expect(({ body }: { body: DeliveryPollBody }) => {
        expect(body.deliveries).toEqual([]);
      });

    await expect(
      agentRepository.findOneByOrFail({ id: agent.id }),
    ).resolves.toMatchObject({
      status: AgentStatus.Online,
    });
  });

  it('retries webhook deliveries without ACK and eventually dead-letters them', async () => {
    const receivedRequests: Array<{
      headers: Record<string, string | string[] | undefined>;
      body: string;
    }> = [];
    const webhookServer = createServer((requestStream, responseStream) => {
      let body = '';
      requestStream.setEncoding('utf8');
      requestStream.on('data', (chunk) => {
        body += chunk;
      });
      requestStream.on('end', () => {
        receivedRequests.push({
          headers: requestStream.headers,
          body,
        });
        responseStream.writeHead(200);
        responseStream.end('ok');
      });
    });
    await new Promise<void>((resolve) =>
      webhookServer.listen(0, '127.0.0.1', resolve),
    );
    const webhookAddress = typedValue<AddressInfo>(webhookServer.address());
    const webhookUrl = `http://127.0.0.1:${webhookAddress.port}/deliveries`;

    try {
      const sender = await importSelfAgent(
        app,
        'delivery-webhook-sender',
        'Delivery Webhook Sender',
      );
      const recipient = await importSelfAgent(
        app,
        'delivery-webhook-recipient',
        'Delivery Webhook Recipient',
      );
      await policyService.upsertAgentSafetyPolicy(recipient.id, {
        dmAcceptanceMode: AgentDmAcceptanceMode.Open,
      });
      const senderClaim = await claimFederatedAgent(
        app,
        federationCredentialsService,
        sender.id,
        {
          pollingEnabled: true,
        },
      );
      await claimFederatedAgent(
        app,
        federationCredentialsService,
        recipient.id,
        {
          transportMode: 'webhook',
          webhookUrl,
        },
      );

      const actionResponse = await request(app.getHttpServer())
        .post('/api/v1/actions')
        .set('Authorization', `Bearer ${senderClaim.accessToken}`)
        .set('Idempotency-Key', 'delivery-webhook-1')
        .send({
          type: 'dm.send',
          payload: {
            targetType: 'agent',
            targetId: recipient.id,
            content: 'Webhook without ack',
          },
        })
        .expect(202);
      const actionResponseBody = typedValue<AcceptedActionBody>(
        actionResponse.body,
      );

      await waitForActionStatus(
        app,
        senderClaim.accessToken,
        actionResponseBody.id,
      );

      const deadLetterDelivery = await waitForDeadLetter(
        deliveryRepository,
        recipient.id,
      );

      expect(receivedRequests.length).toBeGreaterThanOrEqual(2);
      expect(receivedRequests[0].headers['x-agents-chat-signature']).toEqual(
        expect.any(String),
      );
      expect(receivedRequests[0].headers['x-agents-chat-timestamp']).toEqual(
        expect.any(String),
      );
      expect(receivedRequests[0].headers['x-agents-chat-delivery-id']).toEqual(
        expect.any(String),
      );
      const webhookPayload = typedValue<{
        delivery: {
          event: {
            type: string;
          };
        };
      }>(JSON.parse(receivedRequests[0].body) as unknown);
      expect(webhookPayload.delivery.event.type).toBe('dm.received');
      expect(deadLetterDelivery.status).toBe(DeliveryStatus.DeadLetter);

      const dmEvents = await eventRepository.findBy({
        eventType: 'dm.send',
        actorAgentId: sender.id,
      });
      expect(dmEvents).toHaveLength(1);
    } finally {
      await new Promise<void>((resolve, reject) => {
        webhookServer.close((error) => {
          if (error) {
            reject(error);
            return;
          }

          resolve();
        });
      });
    }
  });
});

async function waitForDeadLetter(
  deliveryRepository: Repository<DeliveryEntity>,
  recipientAgentId: string,
  timeoutMs = 2_000,
) {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    const deliveries = await deliveryRepository.findBy({ recipientAgentId });
    const deadLetter = deliveries.find(
      (delivery) => delivery.status === DeliveryStatus.DeadLetter,
    );

    if (deadLetter) {
      return deadLetter;
    }

    await new Promise((resolve) => setTimeout(resolve, 50));
  }

  throw new Error(
    `Timed out waiting for recipient ${recipientAgentId} to dead-letter a delivery.`,
  );
}
