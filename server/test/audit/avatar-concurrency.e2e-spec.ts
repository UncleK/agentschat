import request from 'supertest';
import { randomUUID } from 'node:crypto';
import {
  createTestApplication,
  TestApplicationContext,
} from '../support/test-app';
import { auditBody, AuditResponse } from './audit-response';
import { approveBinding } from './control-test-support';
import {
  registerHuman,
  waitForActionStatus,
} from '../federation/support/federation-test-support';
import { AgentDmAcceptanceMode } from '../../src/database/domain.enums';
import { EventEntity } from '../../src/database/entities/event.entity';
import { PolicyService } from '../../src/modules/policy/policy.service';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { AssetStorageService } from '../../src/modules/assets/asset-storage.service';
import { onePixelPngBuffer } from '../assets/support/image-upload-test-support';

// Only the scheduling barrier is mocked. All HTTP, object bytes, ORM writes,
// transactions and final assertions use the isolated backend/PostgreSQL/MinIO.
describe('RR-01 avatar publication concurrency (PostgreSQL)', () => {
  let ctx: TestApplicationContext;
  beforeAll(async () => {
    ctx = await createTestApplication();
  });
  afterAll(async () => {
    await ctx?.close();
  });
  afterEach(() => jest.restoreAllMocks());
  const api = () => request(ctx.app.getHttpServer());
  const row = (id: string) =>
    ctx.dataSource.getRepository(AgentEntity).findOneByOrFail({ id });
  async function connected() {
    const b = auditBody(
      (
        await api()
          .post('/api/v1/agents/bootstrap/public')
          .send({
            handle: `race-${randomUUID().slice(0, 8)}`,
            displayName: 'Avatar race',
          })
          .expect(201)
      ).body,
    );
    return auditBody(
      (
        await api()
          .post('/api/v1/agents/claim')
          .send({ claimToken: b.bootstrap.claimToken, pollingEnabled: true })
          .expect(201)
      ).body,
    );
  }
  async function owner(c: AuditResponse) {
    const h = await registerHuman(
      ctx.app,
      `${randomUUID()}@example.test`,
      'Synthetic owner',
    );
    const b = auditBody(
      (
        await api()
          .post(`/api/v1/agents/${c.agent.id}/claim-requests`)
          .set('Authorization', `Bearer ${h.accessToken}`)
          .expect(201)
      ).body,
    );
    await approveBinding(
      ctx.app,
      h.accessToken,
      c.accessToken,
      c.agent.id,
      b.claimRequest.id,
      b.challengeToken,
    );
    return h;
  }
  async function upload(c: AuditResponse, rejected = false) {
    const b = auditBody(
      (
        await api()
          .post('/api/v1/agents/self/avatar-upload')
          .set('Authorization', `Bearer ${c.accessToken}`)
          .send({
            fileName: rejected ? 'nsfw-scene.png' : 'safe.png',
            mimeType: 'image/png',
          })
          .expect(201)
      ).body,
    );
    expect(
      (
        await fetch(b.upload.url, {
          method: 'PUT',
          headers: { 'Content-Type': 'image/png' },
          body: onePixelPngBuffer,
        })
      ).ok,
    ).toBe(true);
    return b.upload.objectKey;
  }
  function complete(c: AuditResponse) {
    return api()
      .post('/api/v1/agents/self/avatar-upload/complete')
      .set('Authorization', `Bearer ${c.accessToken}`);
  }
  function barrier() {
    let enter!: () => void;
    let release!: () => void;
    const entered = new Promise<void>((r) => {
      enter = r;
    });
    const resumed = new Promise<void>((r) => {
      release = r;
    });
    const storage = ctx.app.get(AssetStorageService);
    const head = storage.headObject.bind(storage);
    jest.spyOn(storage, 'headObject').mockImplementationOnce(async (input) => {
      const result = await head(input);
      enter();
      await resumed;
      return result;
    });
    return { entered, release };
  }
  it.each([false, true])(
    'RR1-01/03 keeps a committed emergency stop during completion (rejected=%s)',
    async (rejected) => {
      const c = await connected();
      const h = await owner(c);
      await upload(c, rejected);
      const gate = barrier();
      const pending = complete(c).then((r) => r);
      await gate.entered;
      try {
        await api()
          .patch(`/api/v1/agents/${c.agent.id}/safety-policy`)
          .set('Authorization', `Bearer ${h.accessToken}`)
          .send({ emergencyStopDmResponses: true })
          .expect(200);
      } finally {
        gate.release();
      }
      expect((await pending).status).toBe(rejected ? 403 : 200);
      expect(
        (await row(c.agent.id)).profileMetadata.emergencyStopDmResponses,
      ).toBe(true);
    },
  );
  it.each([false, true])(
    'RR1-02/03 keeps a legal binding and private profile during completion (rejected=%s)',
    async (rejected) => {
      const c = await connected();
      const peer = await connected();
      await ctx.app.get(PolicyService).upsertAgentSafetyPolicy(peer.agent.id, {
        dmAcceptanceMode: AgentDmAcceptanceMode.Open,
      });
      const sent = auditBody(
        (
          await api()
            .post('/api/v1/actions')
            .set('Authorization', `Bearer ${c.accessToken}`)
            .set('Idempotency-Key', randomUUID())
            .send({
              type: 'dm.send',
              payload: {
                targetType: 'agent',
                targetId: peer.agent.id,
                content: 'PRIVATE avatar barrier history',
              },
            })
            .expect(202)
        ).body,
      );
      expect(
        (await waitForActionStatus(ctx.app, c.accessToken, sent.id)).status,
      ).toBe('succeeded');
      const history = await ctx.dataSource
        .getRepository(EventEntity)
        .findOneByOrFail({
          actorAgentId: c.agent.id,
          content: 'PRIVATE avatar barrier history',
        });
      const stranger = await registerHuman(
        ctx.app,
        `${randomUUID()}@example.test`,
        'Unrelated viewer',
      );
      const historyUrl = `/api/v1/content/dm/threads/${history.threadId}/messages?activeAgentId=${c.agent.id}`;
      await api()
        .get(historyUrl)
        .set('Authorization', `Bearer ${stranger.accessToken}`)
        .expect(403);
      await ctx.dataSource
        .getRepository(AgentEntity)
        .update(c.agent.id, { isPublic: false });
      await upload(c, rejected);
      const gate = barrier();
      const pending = complete(c).then((r) => r);
      await gate.entered;
      let h: Awaited<ReturnType<typeof owner>>;
      try {
        h = await owner(c);
      } finally {
        gate.release();
      }
      expect((await pending).status).toBe(rejected ? 403 : 200);
      const saved = await row(c.agent.id);
      expect(saved.ownerType).toBe('human');
      expect(saved.ownerUserId).toBe(h.user.id);
      expect(saved.isPublic).toBe(false);
      expect(saved.id).toBe(c.agent.id);
      expect(
        await ctx.dataSource
          .getRepository(EventEntity)
          .findOneByOrFail({ id: history.id }),
      ).toEqual(history);
      await api()
        .get(historyUrl)
        .set('Authorization', `Bearer ${h.accessToken}`)
        .expect(200);
      await api()
        .get(historyUrl)
        .set('Authorization', `Bearer ${stranger.accessToken}`)
        .expect(403);
    },
  );
  it.each([false, true])(
    'RR1-04 old completion cannot publish or clear a newer pending upload (rejected=%s)',
    async (rejected) => {
      const c = await connected();
      await upload(c, rejected);
      const gate = barrier();
      const pending = complete(c).then((r) => r);
      await gate.entered;
      let next: string;
      try {
        next = await upload(c);
      } finally {
        gate.release();
      }
      expect((await pending).status).toBe(409);
      expect(JSON.stringify((await row(c.agent.id)).profileMetadata)).toContain(
        next,
      );
      await complete(c).expect(200);
      await complete(c).expect(409);
      await api()
        .get(`/api/v1/agents/${c.agent.id}/avatar`)
        .expect(200)
        .expect('Content-Type', 'image/png');
    },
  );
  it('RR1-04 an expired upload cannot publish', async () => {
    const c = await connected();
    await upload(c);
    await ctx.dataSource.query(
      "UPDATE agents SET profile_metadata=jsonb_set(profile_metadata, '{pendingAvatarUpload,expiresAt}', to_jsonb('2000-01-01T00:00:00Z'::text)) WHERE id=$1",
      [c.agent.id],
    );
    await complete(c).expect(409);
  });
  it('RR1-04 duplicate in-flight completion publishes only once', async () => {
    const c = await connected();
    await upload(c);
    const gate = barrier();
    const pending = complete(c).then((r) => r);
    await gate.entered;
    try {
      await complete(c).expect(200);
    } finally {
      gate.release();
    }
    expect((await pending).status).toBe(409);
  });
  it('RR-01 other stale save: invitation refresh cannot undo a concurrent connection and owner policy', async () => {
    const h = await registerHuman(
      ctx.app,
      `${randomUUID()}@example.test`,
      'Invitation owner',
    );
    const invite = () =>
      api()
        .post('/api/v1/agents/import/human/invitations')
        .set('Authorization', `Bearer ${h.accessToken}`);
    const first = auditBody((await invite().expect(201)).body);
    const repository = ctx.dataSource.getRepository(AgentEntity);
    const original = repository.find.bind(repository);
    let enter!: () => void;
    let release!: () => void;
    const entered = new Promise<void>((r) => {
      enter = r;
    });
    const resumed = new Promise<void>((r) => {
      release = r;
    });
    jest.spyOn(repository, 'find').mockImplementationOnce(async (id) => {
      const result = await original(id);
      enter();
      await resumed;
      return result;
    });
    const refresh = invite().then((r) => r);
    await entered;
    let c: AuditResponse;
    try {
      c = auditBody(
        (
          await api()
            .post('/api/v1/agents/claim')
            .send({
              claimToken: first.invitation.claimToken,
              pollingEnabled: true,
            })
            .expect(201)
        ).body,
      );
      await api()
        .patch(`/api/v1/agents/${c.agent.id}/safety-policy`)
        .set('Authorization', `Bearer ${h.accessToken}`)
        .send({ emergencyStopDmResponses: true })
        .expect(200);
    } finally {
      release();
    }
    expect((await refresh).status).toBe(201);
    const saved = await row(c.agent.id);
    expect(saved.profileMetadata.emergencyStopDmResponses).toBe(true);
    expect(saved.profileMetadata.invitationPending).toBe(false);
    expect(saved.status).toBe('online');
  });
});
