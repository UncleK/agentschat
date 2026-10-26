import { randomBytes, randomUUID } from 'node:crypto';
import request from 'supertest';
import { AgentConnectionEntity } from '../../src/database/entities/agent-connection.entity';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { AgentStatus } from '../../src/database/domain.enums';
import { DeliveryEntity } from '../../src/database/entities/delivery.entity';
import { EventEntity } from '../../src/database/entities/event.entity';
import { readDeliveryHealth } from '../../src/database/delivery-health';
import { ContinuousParticipationService } from '../../src/modules/federation/continuous-participation.service';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import { FederationDeliveryService } from '../../src/modules/federation/federation-delivery.service';
import * as transport from '../../src/modules/federation/webhook-http';
import {
  createTestApplication,
  typedValue,
  type TestApplicationContext,
} from '../support/test-app';

type Challenge = { verificationId: string; nonce: string; runId?: string };
type State = {
  state: string;
  enabled: boolean;
  planId: string;
  expiresAt: string;
  hostTaskId: string | null;
};

describe('Verified continuous participation', () => {
  let ctx: TestApplicationContext;
  let service: ContinuousParticipationService;
  const canonical = 'http://127.0.0.1:3310';
  const previousOrigin = process.env.CONNECTOR_PUBLIC_BASE_URL;
  beforeAll(async () => {
    process.env.CONNECTOR_PUBLIC_BASE_URL = canonical;
    ctx = await createTestApplication();
    service = ctx.app.get(ContinuousParticipationService);
    const delivery = ctx.app.get(FederationDeliveryService);
    clearInterval(delivery['deliverySweepTimer']);
    delivery['deliverySweepTimer'] = null;
    jest.spyOn(delivery, 'poke').mockImplementation(() => undefined);
  });
  afterAll(async () => {
    jest.restoreAllMocks();
    await ctx?.close();
    if (previousOrigin === undefined)
      delete process.env.CONNECTOR_PUBLIC_BASE_URL;
    else process.env.CONNECTOR_PUBLIC_BASE_URL = previousOrigin;
  });
  const path = '/api/v1/connectors/participation';
  const options = {
    enabled: true,
    authorized: true,
    mode: 'host_schedule',
    hostScheduleId: 'real-host-task-fixture',
  };
  async function join(webhook = false) {
    const response = await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/connect')
      .send({
        handle: 'return-' + randomUUID().slice(0, 8),
        displayName: 'Return fixture',
        recoveryKey: randomBytes(32).toString('hex'),
        ...(webhook
          ? {
              transportMode: 'hybrid',
              webhookUrl: 'https://return.audit.invalid/events',
            }
          : {}),
      })
      .expect(201);
    const identity = typedValue<{ accessToken: string; agent: { id: string } }>(
      response.body,
    );
    const agent = await ctx.app
      .get(FederationCredentialsService)
      .authenticateAgentToken(identity.accessToken);
    return {
      ...identity,
      auth: agent,
      connection: () =>
        ctx.dataSource
          .getRepository(AgentConnectionEntity)
          .findOneByOrFail({ id: agent.connectionId }),
    };
  }
  function configure(token: string, body: object, status = 200) {
    return request(ctx.app.getHttpServer())
      .post(path)
      .set('Authorization', 'Bearer ' + token)
      .send(body)
      .expect(status);
  }
  function confirm(token: string, challenge: Challenge, status = 200) {
    return request(ctx.app.getHttpServer())
      .post(path + '/confirm')
      .set('Authorization', 'Bearer ' + token)
      .send({ ...challenge, runId: challenge.runId ?? 'actual-return-fixture' })
      .expect(status);
  }
  async function changePlan(
    a: Awaited<ReturnType<typeof join>>,
    patch: object,
  ) {
    const c = await a.connection();
    await ctx.dataSource.getRepository(AgentConnectionEntity).update(c.id, {
      continuousParticipation: { ...c.continuousParticipation!, ...patch },
    });
  }
  async function returned(a: Awaited<ReturnType<typeof join>>) {
    await changePlan(a, { probeNotBefore: new Date(0).toISOString() });
    const inbox = await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/inbox')
      .set('Authorization', 'Bearer ' + a.accessToken)
      .expect(200);
    expect(inbox.headers['cache-control']).toBe('no-store');
    return typedValue<{ participationVerification: Challenge }>(inbox.body)
      .participationVerification;
  }

  it('requires opt-in and a real task; delayed authenticated confirmation is separate from configuration and idempotent', async () => {
    const a = await join();
    expect(await service.read(a.auth)).toMatchObject({
      state: 'not_configured',
      enabled: false,
      hostScheduleCreatedByPlatform: false,
    });
    await configure(a.accessToken, { enabled: true }, 400);
    const missing = await configure(a.accessToken, {
      enabled: true,
      authorized: true,
    });
    expect(missing.body).toMatchObject({
      state: 'needs_host_setup',
      enabled: false,
    });
    const first = await configure(a.accessToken, options);
    expect(first.body).toMatchObject({
      state: 'awaiting_confirmation',
      enabled: false,
      hostTaskId: options.hostScheduleId,
    });
    const repeated = await configure(a.accessToken, options);
    expect(repeated.body).toMatchObject({
      planId: typedValue<State>(first.body).planId,
      expiresAt: typedValue<State>(first.body).expiresAt,
    });
    // The setup response cannot disclose the private verification challenge.
    const stored = (await a.connection()).continuousParticipation!;
    expect(JSON.stringify(first.body)).not.toContain(stored.probeNonce);
    await changePlan(a, {
      probeNotBefore: new Date(Date.now() + 60000).toISOString(),
    });
    expect(await service.pollVerification(a.auth)).toBeNull();
    const challenge = await returned(a);
    await confirm(a.accessToken, { ...challenge, nonce: '0'.repeat(64) }, 409);
    const b = await join();
    await confirm(b.accessToken, challenge, 409);
    const verified = await confirm(a.accessToken, challenge);
    expect(verified.body).toMatchObject({
      state: 'enabled',
      enabled: true,
      verification: 'delayed_authenticated_return',
    });
    await confirm(a.accessToken, challenge);
    expect(await service.pollVerification(a.auth)).toBeNull();
    expect(JSON.stringify(await service.read(a.auth))).not.toContain(
      challenge.nonce,
    );
    await configure(a.accessToken, { enabled: false });
    await confirm(a.accessToken, challenge, 409);
  });

  it('rejects expired, rotated and suspended identities and never renews a plan on ordinary reads', async () => {
    const a = await join();
    await configure(a.accessToken, options);
    const challenge = await returned(a);
    await changePlan(a, { probeExpiresAt: new Date(0).toISOString() });
    await confirm(a.accessToken, challenge, 409);
    expect(await service.read(a.auth)).toMatchObject({
      state: 'verification_expired',
    });
    await changePlan(a, { expiresAt: new Date(0).toISOString() });
    expect(await service.read(a.auth)).toMatchObject({
      state: 'expired',
      enabled: false,
    });
    await configure(a.accessToken, options);
    const next = await returned(a);
    await ctx.dataSource
      .getRepository(AgentEntity)
      .update(a.agent.id, { status: AgentStatus.Suspended });
    await confirm(a.accessToken, next, 403);
    await ctx.dataSource
      .getRepository(AgentEntity)
      .update(a.agent.id, { status: AgentStatus.Offline });
    await ctx.dataSource
      .getRepository(AgentConnectionEntity)
      .update(a.auth.connectionId, { tokenHash: 'rotated-token' });
    await confirm(a.accessToken, next, 401);
    await expect(
      service.confirm(a.auth, { ...next, runId: 'stale-runtime' }),
    ).rejects.toMatchObject({ status: 401 });
  });

  it('requires runtime confirmation after signed callback receipt and bounds unacknowledged wakes', async () => {
    const a = await join(true);
    const before = await ctx.dataSource.getRepository(EventEntity).count();
    const beforeDeliveries = await ctx.dataSource
      .getRepository(DeliveryEntity)
      .count();
    const send = jest
      .spyOn(transport, 'postWebhook')
      .mockResolvedValue({ ok: true, status: 200 });
    try {
      const first = await configure(a.accessToken, {
        enabled: true,
        authorized: true,
        mode: 'webhook',
      });
      expect(first.body).toMatchObject({
        state: 'awaiting_confirmation',
        enabled: false,
      });
      expect(send).toHaveBeenCalledTimes(1);
      const [url, body, headers] = send.mock.calls[0];
      expect(url).toBe('https://return.audit.invalid/events');
      const c = await a.connection();
      expect(headers['x-agents-chat-signature']).toBe(
        ctx.app
          .get(FederationCredentialsService)
          .signWebhookPayload(
            c.webhookSecret!,
            headers['x-agents-chat-timestamp'],
            body,
          ),
      );
      const probe = typedValue<{
        type: string;
        participationVerification: Challenge;
      }>(JSON.parse(body));
      expect(probe.type).toBe('agentschat.continuous.verify');
      expect(await service.pollVerification(a.auth)).toBeNull();
      expect(await service.reserveWake(c)).toBe(false);
      await configure(a.accessToken, {
        enabled: true,
        authorized: true,
        mode: 'webhook',
      });
      expect(send).toHaveBeenCalledTimes(1);
      await confirm(a.accessToken, probe.participationVerification);
      expect(await service.reserveWake(c)).toBe(true);
      expect(await service.reserveWake(c)).toBe(false);
      await service.recordAcknowledgement(c.id);
      expect(
        (await a.connection()).continuousParticipation?.unacknowledgedWakeups,
      ).toBe(0);
      for (let i = 0; i < 3; i++) {
        await changePlan(a, { lastWakeAt: new Date(0).toISOString() });
        expect(await service.reserveWake(c)).toBe(true);
      }
      await changePlan(a, { lastWakeAt: new Date(0).toISOString() });
      expect(await service.reserveWake(c)).toBe(false);
      expect(await service.read(a.auth)).toMatchObject({
        state: 'paused',
        reason: 'missing_acknowledgement',
      });
      await confirm(a.accessToken, probe.participationVerification, 409);
      expect(await ctx.dataSource.getRepository(EventEntity).count()).toBe(
        before,
      );
      expect(await ctx.dataSource.getRepository(DeliveryEntity).count()).toBe(
        beforeDeliveries,
      );
      const health = JSON.stringify(await readDeliveryHealth(ctx.dataSource));
      for (const secret of [
        probe.participationVerification.nonce,
        c.tokenHash,
        c.webhookSecret!,
        c.webhookUrl!,
      ])
        expect(health).not.toContain(secret);
    } finally {
      send.mockRestore();
    }
  });

  it('preserves an early verification when the callback response fails later, and invalidates changed channels', async () => {
    const a = await join(true);
    const send = jest
      .spyOn(transport, 'postWebhook')
      .mockImplementation(async (_url, body) => {
        const probe = typedValue<{ participationVerification: Challenge }>(
          JSON.parse(body),
        );
        await service.confirm(a.auth, {
          ...probe.participationVerification,
          runId: 'actual-callback-run',
        });
        return { ok: false, status: 503 };
      });
    try {
      expect(
        (
          await configure(a.accessToken, {
            enabled: true,
            authorized: true,
            mode: 'webhook',
          })
        ).body,
      ).toMatchObject({ state: 'enabled' });
      const stale = await a.connection();
      await request(ctx.app.getHttpServer())
        .post('/api/v1/agents/connection/transport')
        .set('Authorization', 'Bearer ' + a.accessToken)
        .send({
          transportMode: 'hybrid',
          webhookUrl: 'https://changed.audit.invalid/events',
        })
        .expect(200);
      expect(await service.read(a.auth)).toMatchObject({
        state: 'needs_reverification',
        enabled: false,
      });
      expect(await service.reserveWake(stale)).toBe(false);
      expect(await service.reserveWake(await a.connection())).toBe(false);
      await configure(a.accessToken, { enabled: false, mode: 'host_schedule' });
      expect(await service.read(a.auth)).toMatchObject({
        mode: 'webhook',
        state: 'paused',
      });
      expect(await service.reserveWake(await a.connection())).toBe(false);
      await configure(a.accessToken, options);
      expect(await service.reserveWake(await a.connection())).toBe(false);
    } finally {
      send.mockRestore();
    }
  });

  it('pauses a failed verification and refuses immediate repeated callback tests', async () => {
    const a = await join(true);
    const send = jest
      .spyOn(transport, 'postWebhook')
      .mockRejectedValue(new Error('offline'));
    try {
      expect(
        (
          await configure(a.accessToken, {
            enabled: true,
            authorized: true,
            mode: 'webhook',
          })
        ).body,
      ).toMatchObject({ state: 'paused', reason: 'callback_test_failed' });
      await configure(
        a.accessToken,
        { enabled: true, authorized: true, mode: 'webhook' },
        429,
      );
      expect(send).toHaveBeenCalledTimes(1);
    } finally {
      send.mockRestore();
    }
  });

  it('allows community credentials to manage host tasks, not Webhook controls', async () => {
    const a = await join(true);
    const community = { ...a.auth, credentialKind: 'community' as const };
    await expect(
      service.configure(community, {
        enabled: true,
        authorized: true,
        mode: 'webhook',
      }),
    ).rejects.toMatchObject({ status: 403 });
    expect(await service.configure(community, options)).toMatchObject({
      state: 'awaiting_confirmation',
      mode: 'host_schedule',
    });
    const send = jest
      .spyOn(transport, 'postWebhook')
      .mockResolvedValue({ ok: true, status: 200 });
    try {
      await configure(a.accessToken, {
        enabled: true,
        authorized: true,
        mode: 'webhook',
      });
      await expect(
        service.configure(community, { enabled: false }),
      ).rejects.toMatchObject({ status: 403 });
      const probe = typedValue<{ participationVerification: Challenge }>(
        JSON.parse(send.mock.calls[0][1]),
      );
      await expect(
        service.confirm(community, {
          ...probe.participationVerification,
          runId: 'community',
        }),
      ).rejects.toMatchObject({ status: 403 });
    } finally {
      send.mockRestore();
    }
  });

  it('keeps browser configuration behind origin and CSRF checks and shows unverified setup honestly', async () => {
    const a = await join();
    const browser = request.agent(ctx.app.getHttpServer());
    const page = await browser.get('/api/v1/connectors/browser').expect(200);
    const ticket = page.text.match(/name="ticket" value="([^"]+)"/)![1];
    await browser
      .post('/api/v1/connectors/browser/connect')
      .set('Origin', canonical)
      .type('form')
      .send({ ticket, mode: 'existing', accessToken: a.accessToken })
      .expect(303);
    const joined = await browser.get('/api/v1/connectors/browser').expect(200);
    const current = joined.text.match(/name="ticket" value="([^"]+)"/)![1];
    const form = {
      ticket: current,
      enabled: 'true',
      authorized: 'on',
      hostScheduleId: 'actual-browser-host-task',
    };
    await browser
      .post('/api/v1/connectors/browser/participation')
      .set('Origin', canonical)
      .type('form')
      .send({ ...form, ticket: 'forged' })
      .expect(400);
    await browser
      .post('/api/v1/connectors/browser/participation')
      .set('Origin', 'https://evil.example')
      .type('form')
      .send(form)
      .expect(401);
    await browser
      .post('/api/v1/connectors/browser/participation')
      .set('Origin', canonical)
      .type('form')
      .send(form)
      .expect(303);
    const pending = await browser.get('/api/v1/connectors/browser').expect(200);
    expect(pending.text).toContain('等待实际回访验证');
    expect(pending.headers['cache-control']).toContain('no-store');
  });
});
