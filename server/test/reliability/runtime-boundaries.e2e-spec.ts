// Only transport is replaced: production URL validation remains active.
jest.mock('../../src/modules/federation/webhook-http', () => {
  const real = jest.requireActual<
    typeof import('../../src/modules/federation/webhook-http')
  >('../../src/modules/federation/webhook-http');
  return {
    ...real,
    postWebhook: async (
      url: string,
      body: string,
      headers: Record<string, string>,
      signal: AbortSignal,
    ) => {
      const match = /^https:\/\/webhook\.fixture\/(\d+)(\/.*)$/.exec(url);
      if (!match) throw new Error('Unexpected synthetic webhook target');
      const result = await fetch(`http://127.0.0.1:${match[1]}${match[2]}`, {
        method: 'POST',
        body,
        headers,
        signal,
        redirect: 'error',
      });
      await result.body?.cancel();
      return { ok: result.ok, status: result.status };
    },
  };
});
import { createHmac } from 'node:crypto';
import { createServer } from 'node:http';
import { AddressInfo } from 'node:net';
import request from 'supertest';
import { APP_ENVIRONMENT, AppEnvironment } from '../../src/config/environment';
import {
  DeliveryChannel,
  DeliveryStatus,
  FollowTargetType,
  AgentStatus,
  EventActorType,
  EventContentType,
  SubjectType,
  ThreadContextType,
  ThreadParticipantRole,
} from '../../src/database/domain.enums';
import { FollowEntity } from '../../src/database/entities/follow.entity';
import { AgentDirectoryResponse } from '../../src/modules/agents/agents.service';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { AgentConnectionEntity } from '../../src/database/entities/agent-connection.entity';
import { DeliveryEntity } from '../../src/database/entities/delivery.entity';
import { EventEntity } from '../../src/database/entities/event.entity';
import { ThreadEntity } from '../../src/database/entities/thread.entity';
import { ThreadParticipantEntity } from '../../src/database/entities/thread-participant.entity';
import { UserEntity } from '../../src/database/entities/user.entity';
import { AuthEmailDeliveryService } from '../../src/modules/auth/auth-email-delivery.service';
import { AgentsService } from '../../src/modules/agents/agents.service';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import { FederationService } from '../../src/modules/federation/federation.service';
import type { AuthenticatedFederatedAgent } from '../../src/modules/federation/federation.types';
import { FederationDeliveryService } from '../../src/modules/federation/federation-delivery.service';
import { NotificationsService } from '../../src/modules/notifications/notifications.service';
import { RealtimeService } from '../../src/modules/realtime/realtime.service';
import {
  createTestApplication,
  TestApplicationContext,
  typedValue,
} from '../support/test-app';
import {
  registerHuman,
  importSelfAgent,
  claimFederatedAgent,
  waitForActionStatus,
} from '../federation/support/federation-test-support';

type RuntimeStatus = Awaited<ReturnType<AgentsService['readRuntimeStatus']>>;
interface ClientSocket {
  onopen: (() => void) | null;
  onmessage: ((event: { data: string }) => void) | null;
  onerror: (() => void) | null;
  onclose: ((event: { code: number }) => void) | null;
  close: () => void;
}
const pause = (ms: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, ms));
async function until(
  check: () => Promise<boolean> | boolean,
  timeoutMs = 3000,
) {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    if (await check()) return;
    await pause(20);
  }
  throw new Error('Timed out waiting for the runtime boundary.');
}

describe('Authentication, delivery and owner runtime boundaries (e2e)', () => {
  let context: TestApplicationContext;
  const sockets: ClientSocket[] = [];
  beforeAll(async () => {
    context = await createTestApplication();
    await context.app.listen(0, '127.0.0.1');
  });
  afterAll(async () => {
    for (const socket of sockets) socket.close();
    await context?.close();
  });
  async function openSocket(token: string) {
    const address = typedValue<AddressInfo>(
      typedValue<{ address: () => unknown }>(
        context.app.getHttpServer(),
      ).address(),
    );
    const Socket = (
      globalThis as unknown as { WebSocket: new (url: string) => ClientSocket }
    ).WebSocket;
    const socket = new Socket(
      `ws://127.0.0.1:${address.port}/ws?access_token=${token}`,
    );
    sockets.push(socket);
    const received: string[] = [];
    const state = { closeCode: null as number | null };
    socket.onmessage = (event) => received.push(event.data);
    socket.onclose = (event) => {
      state.closeCode = event.code;
    };
    await new Promise<void>((resolve, reject) => {
      socket.onopen = resolve;
      socket.onerror = () => reject(new Error('WebSocket failed to connect.'));
    });
    await until(() =>
      received.some((value) => value.includes('realtime.connected')),
    );
    return { socket, received, state };
  }
  async function newEvent(threadId?: string) {
    const threads = context.dataSource.getRepository(ThreadEntity);
    const thread = threadId
      ? { id: threadId }
      : await threads.save(
          threads.create({ contextType: ThreadContextType.DirectMessage }),
        );
    const events = context.dataSource.getRepository(EventEntity);
    return events.save(
      events.create({
        threadId: thread.id,
        eventType: 'dm.send',
        actorType: EventActorType.System,
        contentType: EventContentType.Text,
        content: 'Private local regression content',
        occurredAt: new Date(),
      }),
    );
  }
  async function ownedAgent(
    owner: Awaited<ReturnType<typeof registerHuman>>,
    handle: string,
  ) {
    return request(context.app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({ handle, displayName: handle })
      .expect(201)
      .then(({ body }) => typedValue<{ id: string }>(body));
  }

  it('closes existing sockets on a real password reset and rejects the old HTTP token', async () => {
    const human = await registerHuman(
      context.app,
      'reset-socket@example.test',
      'Reset Socket',
    );
    const socket = await openSocket(human.accessToken);
    let code = '';
    const delivery = jest
      .spyOn(context.app.get(AuthEmailDeliveryService), 'sendPasswordResetCode')
      .mockImplementation((input) => {
        code = input.code;
        return Promise.resolve();
      });
    try {
      await request(context.app.getHttpServer())
        .post('/api/v1/auth/password-reset/request')
        .send({ email: human.user.email })
        .expect(200);
      expect(code).toMatch(/^\d{6}$/);
      await request(context.app.getHttpServer())
        .post('/api/v1/auth/password-reset/confirm')
        .send({
          email: human.user.email,
          code,
          newPassword: 'changedPassword123',
        })
        .expect(200);
      await until(() => socket.state.closeCode === 1008);
      await request(context.app.getHttpServer())
        .get('/api/v1/auth/me')
        .set('Authorization', `Bearer ${human.accessToken}`)
        .expect(401);
      context.app
        .get(RealtimeService)
        .emitToHuman(human.user.id, { type: 'private.after-reset' });
      await pause(50);
      expect(socket.received.join()).not.toContain('private.after-reset');
    } finally {
      delivery.mockRestore();
    }
  });

  it('closes an idle socket at token expiry without waiting for the next event', async () => {
    const human = await registerHuman(
      context.app,
      'expiry-socket@example.test',
      'Expiry Socket',
    );
    const payload = typedValue<Record<string, unknown>>(
      JSON.parse(
        Buffer.from(human.accessToken.split('.')[1], 'base64url').toString(),
      ),
    );
    payload.exp = Date.now() + 900;
    const encoded = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const env = context.app.get<AppEnvironment>(APP_ENVIRONMENT);
    const token = `v1.${encoded}.${createHmac('sha256', env.auth.jwtSecret).update(encoded).digest('hex')}`;
    const socket = await openSocket(token);
    await until(() => socket.state.closeCode === 1008);
    context.app
      .get(RealtimeService)
      .emitToHuman(human.user.id, { type: 'private.after-expiry' });
    await request(context.app.getHttpServer())
      .get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(401);
    expect(socket.received.join()).not.toContain('private.after-expiry');
  });

  it('checks database revocation before forwarding a private frame from another process', async () => {
    const human = await registerHuman(
      context.app,
      'revoked-socket@example.test',
      'Revoked Socket',
    );
    const socket = await openSocket(human.accessToken);
    await context.dataSource
      .getRepository(UserEntity)
      .increment({ id: human.user.id }, 'authTokenVersion', 1);
    context.app
      .get(RealtimeService)
      .emitToHuman(human.user.id, { type: 'private.after-revocation' });
    await until(() => socket.state.closeCode === 1008);
    expect(socket.received.join()).not.toContain('private.after-revocation');
  });

  it.each(['success', 'http_failure', 'network_failure'])(
    'preserves ACK when a late webhook %s arrives',
    async (mode) => {
      let token = '';
      let requests = 0;
      let responseCompleted = false;
      let handlerError: unknown;
      const webhook = createServer((req, res) => {
        req.resume();
        req.on('end', () => {
          void (async () => {
            requests += 1;
            await request(context.app.getHttpServer())
              .post('/api/v1/acks')
              .set('Authorization', `Bearer ${token}`)
              .send({ deliveryIds: [req.headers['x-agents-chat-delivery-id']] })
              .expect(201);
            await pause(30);
            if (mode === 'network_failure') res.destroy();
            else {
              res.writeHead(mode === 'success' ? 200 : 503);
              res.end();
            }
            responseCompleted = true;
          })().catch((error: unknown) => {
            handlerError = error;
            res.destroy();
          });
        });
      });
      await new Promise<void>((resolve) =>
        webhook.listen(0, '127.0.0.1', resolve),
      );
      try {
        const agent = await importSelfAgent(
          context.app,
          `ack-race-${mode.replaceAll('_', '-')}`,
          'ACK Race',
        );
        const claim = await claimFederatedAgent(
          context.app,
          context.app.get(FederationCredentialsService),
          agent.id,
          {
            transportMode: 'webhook',
            webhookUrl: `https://webhook.fixture/${typedValue<AddressInfo>(webhook.address()).port}/events`,
          },
        );
        token = claim.accessToken;
        const event = await newEvent();
        const queued = await context.app
          .get(FederationDeliveryService)
          .enqueueEventForRecipient(event, agent.id);
        await until(() => responseCompleted || handlerError != null);
        expect(handlerError).toBeUndefined();
        await pause(350);
        const persisted = await context.dataSource
          .getRepository(DeliveryEntity)
          .findOneByOrFail({ id: queued.id });
        expect(persisted).toMatchObject({
          status: DeliveryStatus.Acked,
          nextAttemptAt: null,
          lastError: null,
          deadLetteredAt: null,
          attemptCount: 1,
        });
        expect(persisted.ackedAt).toBeInstanceOf(Date);
        expect(requests).toBe(1);
      } finally {
        webhook.closeAllConnections();
        await new Promise<void>((resolve) => webhook.close(() => resolve()));
      }
    },
  );

  it('times out an unresponsive webhook and records a bounded retry', async () => {
    let requests = 0;
    const webhook = createServer((req) => {
      requests += 1;
      req.resume();
    });
    await new Promise<void>((resolve) =>
      webhook.listen(0, '127.0.0.1', resolve),
    );
    try {
      const agent = await importSelfAgent(
        context.app,
        'webhook-timeout',
        'Webhook Timeout',
      );
      await claimFederatedAgent(
        context.app,
        context.app.get(FederationCredentialsService),
        agent.id,
        {
          transportMode: 'webhook',
          webhookUrl: `https://webhook.fixture/${typedValue<AddressInfo>(webhook.address()).port}/events`,
        },
      );
      const queued = await context.app
        .get(FederationDeliveryService)
        .enqueueEventForRecipient(await newEvent(), agent.id);
      const repository = context.dataSource.getRepository(DeliveryEntity);
      await until(
        async () =>
          (await repository.findOneByOrFail({ id: queued.id })).lastError ===
          'Webhook request timed out.',
      );
      const persisted = await repository.findOneByOrFail({ id: queued.id });
      expect(persisted.attemptCount).toBeGreaterThanOrEqual(1);
      expect(persisted.attemptCount).toBeLessThanOrEqual(2);
      expect(requests).toBeLessThanOrEqual(2);
      await repository.update(
        { id: queued.id },
        {
          status: DeliveryStatus.Acked,
          ackedAt: new Date(),
          nextAttemptAt: null,
          lastError: null,
        },
      );
    } finally {
      webhook.closeAllConnections();
      await new Promise<void>((resolve) => webhook.close(() => resolve()));
    }
  });

  it('restricts diagnostics to the owner and reports current delivery facts without secrets', async () => {
    const owner = await registerHuman(
      context.app,
      'runtime-owner@example.test',
      'Runtime Owner',
    );
    const outsider = await registerHuman(
      context.app,
      'runtime-outsider@example.test',
      'Runtime Outsider',
    );
    const agent = await ownedAgent(owner, 'runtime-owned-agent');
    const url = `/api/v1/agents/${agent.id}/runtime-status`;
    await request(context.app.getHttpServer()).get(url).expect(401);
    await request(context.app.getHttpServer())
      .get(url)
      .set('Authorization', `Bearer ${outsider.accessToken}`)
      .expect(404);
    await request(context.app.getHttpServer())
      .get('/api/v1/agents/invalid/runtime-status')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .expect(400);
    const initial = await request(context.app.getHttpServer())
      .get(url)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .expect(200);
    expect(typedValue<RuntimeStatus>(initial.body).presence.state).toBe(
      'disconnected',
    );
    const claim = await claimFederatedAgent(
      context.app,
      context.app.get(FederationCredentialsService),
      agent.id,
      {
        pollingEnabled: true,
        capabilities: { private: 'fixture-secret-capability' },
      },
    );
    const old = new Date(Date.now() - 600000);
    await context.dataSource
      .getRepository(AgentConnectionEntity)
      .update({ agentId: agent.id }, { lastSeenAt: old, lastHeartbeatAt: old });
    await context.dataSource
      .getRepository(AgentEntity)
      .update({ id: agent.id }, { lastSeenAt: old });
    const repository = context.dataSource.getRepository(DeliveryEntity);
    let sequence = 0;
    for (const status of [
      DeliveryStatus.Pending,
      DeliveryStatus.Sent,
      DeliveryStatus.Retrying,
      DeliveryStatus.DeadLetter,
      DeliveryStatus.Acked,
    ]) {
      const event = await newEvent();
      sequence += 1;
      await repository.insert({
        eventId: event.id,
        recipientAgentId: agent.id,
        sequence,
        status,
        deliveryChannel: DeliveryChannel.Polling,
        replayExpiresAt: new Date(Date.now() + 600000),
        nextAttemptAt:
          status === DeliveryStatus.Acked ||
          status === DeliveryStatus.DeadLetter
            ? null
            : new Date(),
        lastAttemptAt: status === DeliveryStatus.Pending ? null : new Date(),
        ackedAt: status === DeliveryStatus.Acked ? new Date() : null,
        lastError:
          status === DeliveryStatus.DeadLetter
            ? 'https://fixture-secret-token@private.example/callback'
            : null,
      });
    }
    const response = await request(context.app.getHttpServer())
      .get(url)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .expect(200);
    const body = typedValue<RuntimeStatus>(response.body);
    expect(body.presence.state).toBe('stale');
    expect(body.connection).toMatchObject({
      configured: true,
      pollingEnabled: true,
      webhookConfigured: false,
    });
    expect(body.deliveries).toMatchObject({
      pending: 1,
      sent: 1,
      retrying: 1,
      deadLetter: 1,
      acked: 1,
    });
    expect(body.deliveries.lastError?.message).toBe(
      'Delivery failed. Check the connected runtime and network.',
    );
    expect(body.deliveries.lastAttemptAt).toEqual(expect.any(String));
    expect(JSON.stringify(body)).not.toMatch(
      /fixture-secret|private.example|Private local regression content/,
    );
    expect(JSON.stringify(body)).not.toContain(claim.accessToken);
  });

  it('replaces a stale owner spectator with the current owner for DM notifications and historical previews', async () => {
    const oldOwner = await registerHuman(
      context.app,
      'notice-old@example.test',
      'Old Owner',
    );
    const newOwner = await registerHuman(
      context.app,
      'notice-new@example.test',
      'New Owner',
    );
    const member = await registerHuman(
      context.app,
      'notice-member@example.test',
      'Human Member',
    );
    const agent = await ownedAgent(oldOwner, 'notice-transfer-agent');
    const event = await newEvent();
    const participants = context.dataSource.getRepository(
      ThreadParticipantEntity,
    );
    await participants.insert([
      {
        threadId: event.threadId,
        participantType: SubjectType.Agent,
        participantSubjectId: agent.id,
        agentId: agent.id,
        role: ThreadParticipantRole.Member,
      },
      {
        threadId: event.threadId,
        participantType: SubjectType.Human,
        participantSubjectId: oldOwner.user.id,
        userId: oldOwner.user.id,
        role: ThreadParticipantRole.Spectator,
      },
      {
        threadId: event.threadId,
        participantType: SubjectType.Human,
        participantSubjectId: member.user.id,
        userId: member.user.id,
        role: ThreadParticipantRole.Member,
      },
    ]);
    const notifications = context.app.get(NotificationsService);
    await notifications.processEvent(event);
    expect(
      (await notifications.listForHuman(oldOwner.user.id)).notifications,
    ).toHaveLength(1);
    await context.dataSource
      .getRepository(AgentEntity)
      .update({ id: agent.id }, { ownerUserId: newOwner.user.id });
    const oldSocket = await openSocket(oldOwner.accessToken);
    const newSocket = await openSocket(newOwner.accessToken);
    const nextEvent = await newEvent(event.threadId);
    await notifications.processEvent(nextEvent);
    expect(
      (await notifications.listForHuman(newOwner.user.id)).notifications,
    ).toHaveLength(1);
    await until(() =>
      newSocket.received.some((text) => text.includes(nextEvent.id)),
    ).catch(() => {
      throw new Error(
        JSON.stringify({
          received: newSocket.received,
          state: newSocket.state,
          nextEventId: nextEvent.id,
        }),
      );
    });
    expect(oldSocket.received.join()).not.toContain(nextEvent.id);
    expect(
      (await notifications.listForHuman(oldOwner.user.id)).notifications,
    ).toEqual([]);
    expect(await notifications.readBellState(oldOwner.user.id)).toEqual({
      hasUnread: false,
      unreadCount: 0,
    });
    expect(
      (await notifications.listForHuman(newOwner.user.id)).notifications,
    ).toHaveLength(1);
    expect(
      (await notifications.listForHuman(member.user.id)).notifications,
    ).toHaveLength(2);
    expect(
      await participants.countBy({
        threadId: event.threadId,
        userId: newOwner.user.id,
      }),
    ).toBe(0);
  });
  it('looks up public profiles directly and batches directory follower counts and relationships', async () => {
    const first = await importSelfAgent(
      context.app,
      'profile-direct-first',
      'Direct First',
    );
    const second = await importSelfAgent(
      context.app,
      'profile-direct-second',
      'Direct Second',
    );
    const third = await importSelfAgent(
      context.app,
      'profile-direct-third',
      'Direct Third',
    );
    await context.dataSource.getRepository(FollowEntity).insert([
      {
        followerType: SubjectType.Agent,
        followerSubjectId: first.id,
        followerAgentId: first.id,
        targetType: FollowTargetType.Agent,
        targetSubjectId: second.id,
        targetAgentId: second.id,
      },
      {
        followerType: SubjectType.Agent,
        followerSubjectId: second.id,
        followerAgentId: second.id,
        targetType: FollowTargetType.Agent,
        targetSubjectId: first.id,
        targetAgentId: first.id,
      },
      {
        followerType: SubjectType.Agent,
        followerSubjectId: third.id,
        followerAgentId: third.id,
        targetType: FollowTargetType.Agent,
        targetSubjectId: second.id,
        targetAgentId: second.id,
      },
    ]);
    const queries: string[] = [];
    const querySpy = jest
      .spyOn(context.dataSource.logger, 'logQuery')
      .mockImplementation((query) => {
        queries.push(query);
      });
    try {
      const result = await request(context.app.getHttpServer())
        .get('/api/v1/agents/public-directory/profile-direct-second')
        .expect(200);
      expect(
        typedValue<{ agent: { id: string; followerCount: number } }>(
          result.body,
        ).agent,
      ).toMatchObject({ id: second.id, followerCount: 2 });
      expect(
        queries
          .filter((query) => query.includes('FROM "agents"'))
          .every((query) => query.includes('handle')),
      ).toBe(true);
      queries.length = 0;
      const directory = await context.app
        .get(AgentsService)
        .readDirectoryForAgent(first.id);
      expect(
        directory.agents.find((agent) => agent.id === second.id),
      ).toMatchObject({
        followerCount: 2,
        relationship: { viewerFollowsAgent: true, agentFollowsViewer: true },
      });
      expect(
        queries.filter((query) => query.includes('FROM "follows"')),
      ).toHaveLength(2);
      const publicDirectory = await request(context.app.getHttpServer())
        .get('/api/v1/agents/public-directory')
        .expect(200);
      expect(
        typedValue<AgentDirectoryResponse>(publicDirectory.body).agents.find(
          (agent) => agent.id === second.id,
        )?.relationship,
      ).toMatchObject({ viewerFollowsAgent: false, agentFollowsViewer: false });
    } finally {
      querySpy.mockRestore();
    }
    await context.dataSource
      .getRepository(AgentEntity)
      .update({ id: second.id }, { isPublic: false });
    await request(context.app.getHttpServer())
      .get('/api/v1/agents/public-directory/profile-direct-second')
      .expect(404);
    await context.dataSource
      .getRepository(AgentEntity)
      .update({ id: third.id }, { status: AgentStatus.Suspended });
    await request(context.app.getHttpServer())
      .get('/api/v1/agents/public-directory/profile-direct-third')
      .expect(404);
    await request(context.app.getHttpServer())
      .get('/api/v1/agents/public-directory/missing-profile')
      .expect(404);
  });
  it('preserves an actually completed profile update through action retries and polling', async () => {
    const agent = await importSelfAgent(
      context.app,
      'profile-retry-race',
      'Profile Retry Race',
    );
    const session = await claimFederatedAgent(
      context.app,
      context.app.get(FederationCredentialsService),
      agent.id,
      { transportMode: 'polling', pollingEnabled: true },
    );
    for (let iteration = 0; iteration < 3; iteration++) {
      const bio = `Persisted profile ${iteration}`;
      const key = `profile-retry-${iteration}`;
      const body = { type: 'agent.profile.update', payload: { bio } };
      const submit = () =>
        request(context.app.getHttpServer())
          .post('/api/v1/actions')
          .set('Authorization', `Bearer ${session.accessToken}`)
          .set('Idempotency-Key', key)
          .send(body);
      const accepted = await submit().expect(202);
      await Promise.all([
        submit().expect(200),
        submit().expect(200),
        request(context.app.getHttpServer())
          .get('/api/v1/deliveries/poll?wait_seconds=0')
          .set('Authorization', `Bearer ${session.accessToken}`)
          .expect(200),
      ]);
      const result = await waitForActionStatus(
        context.app,
        session.accessToken,
        typedValue<{ id: string }>(accepted.body).id,
      );
      expect(result.status).toBe('succeeded');
      expect(
        (
          await context.dataSource
            .getRepository(AgentEntity)
            .findOneByOrFail({ id: agent.id })
        ).bio,
      ).toBe(bio);
    }
  });

  it.each(['action', 'polling'] as const)(
    '%s activity cannot restore a stale profile, suspension or connection secret',
    async (mode) => {
      const agent = await importSelfAgent(
        context.app,
        `activity-boundary-${mode}`,
        mode,
      );
      await claimFederatedAgent(
        context.app,
        context.app.get(FederationCredentialsService),
        agent.id,
        { transportMode: 'polling', pollingEnabled: true },
      );
      const agents = context.dataSource.getRepository(AgentEntity);
      const connections = context.dataSource.getRepository(
        AgentConnectionEntity,
      );
      const oldAgent = await agents.findOneByOrFail({ id: agent.id });
      const oldConnection = await connections.findOneByOrFail({
        agentId: agent.id,
      });
      const identity: AuthenticatedFederatedAgent = {
        id: agent.id,
        handle: agent.handle,
        connectionId: oldConnection.id,
        transportMode: oldConnection.transportMode,
        pollingEnabled: oldConnection.pollingEnabled,
      };
      // Simulate a read that began before a profile update, suspension and token rotation.
      const readAgent = jest
        .spyOn(agents, 'findOneBy')
        .mockImplementation(() => Promise.resolve({ ...oldAgent }));
      const readConnection = jest
        .spyOn(connections, 'findOneBy')
        .mockImplementation(() => Promise.resolve({ ...oldConnection }));
      const activity = () =>
        mode === 'action'
          ? typedValue<{
              markAgentConnectionActive: (
                agent: AuthenticatedFederatedAgent,
                heartbeat: boolean,
              ) => Promise<void>;
            }>(context.app.get(FederationService)).markAgentConnectionActive(
              identity,
              true,
            )
          : typedValue<{
              recordAgentPollingActivity: (
                agent: AuthenticatedFederatedAgent,
                heartbeat: boolean,
              ) => Promise<void>;
            }>(
              context.app.get(FederationDeliveryService),
            ).recordAgentPollingActivity(identity, true);
      try {
        await agents.update(
          { id: agent.id },
          { bio: 'New profile survives', status: AgentStatus.Suspended },
        );
        await connections.update(
          { id: oldConnection.id },
          { tokenHash: 'rotated-token-fixture', pollingEnabled: false },
        );
        await activity();
        expect(await agents.findOneByOrFail({ id: agent.id })).toMatchObject({
          bio: 'New profile survives',
          status: AgentStatus.Suspended,
        });
        expect(
          await connections.findOneByOrFail({ id: oldConnection.id }),
        ).toMatchObject({
          tokenHash: 'rotated-token-fixture',
          pollingEnabled: false,
        });
        await connections.delete({ id: oldConnection.id });
        await agents.update({ id: agent.id }, { status: AgentStatus.Offline });
        await activity();
        expect(await connections.countBy({ agentId: agent.id })).toBe(0);
        expect((await agents.findOneByOrFail({ id: agent.id })).status).toBe(
          AgentStatus.Offline,
        );
      } finally {
        readAgent.mockRestore();
        readConnection.mockRestore();
      }
    },
  );
});
