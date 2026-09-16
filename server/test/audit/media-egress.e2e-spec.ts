import { auditBody, type AuditResponse } from './audit-response';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import {
  createTestApplication,
  TestApplicationContext,
} from '../support/test-app';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { AssetStorageService } from '../../src/modules/assets/asset-storage.service';
import { onePixelPngBuffer } from '../assets/support/image-upload-test-support';

describe('Audit v1.1 B media and egress', () => {
  let ctx: TestApplicationContext;
  beforeAll(async () => {
    ctx = await createTestApplication();
  });
  afterAll(async () => {
    await ctx?.close();
  });
  const api = () => request(ctx.app.getHttpServer());
  async function bootstrap() {
    return (
      (
        await api()
          .post('/api/v1/agents/bootstrap/public')
          .send({
            handle: `media-${randomUUID().slice(0, 8)}`,
            displayName: 'Synthetic',
          })
          .expect(201)
      ).body as AuditResponse
    ).bootstrap;
  }
  async function connected() {
    const b = await bootstrap();
    return (
      await api()
        .post('/api/v1/agents/claim')
        .send({ claimToken: b.claimToken, pollingEnabled: true })
        .expect(201)
    ).body as AuditResponse;
  }
  it.each([
    'http://127.0.0.1:1',
    'https://127.0.0.1',
    'https://[::1]',
    'https://10.0.0.1',
    'https://169.254.169.254',
    'https://[::ffff:127.0.0.1]',
    'https://user:pass@example.com',
    'https://example.com:9000',
  ])('SS-01 rejects %s without making a network request', async (url) => {
    const b = await bootstrap();
    await api()
      .post('/api/v1/agents/claim')
      .send({
        claimToken: b.claimToken,
        webhookUrl: url,
        transportMode: 'hybrid',
      })
      .expect(400);
  });
  it('AV-01 rejects declared SVG at upload issuance', async () => {
    const c = await connected();
    await api()
      .post('/api/v1/agents/self/avatar-upload')
      .set('Authorization', `Bearer ${c.accessToken}`)
      .send({ fileName: 'canary.svg', mimeType: 'image/svg+xml' })
      .expect(400);
  });
  it('AV-01 rejects active bytes disguised as a PNG', async () => {
    const c = await connected();
    const up = await api()
      .post('/api/v1/agents/self/avatar-upload')
      .set('Authorization', `Bearer ${c.accessToken}`)
      .send({ fileName: 'canary.png', mimeType: 'image/png' })
      .expect(201);
    const put = await fetch(auditBody(up.body).upload.url, {
      method: 'PUT',
      headers: { 'Content-Type': 'image/png' },
      body: '<svg xmlns="http://www.w3.org/2000/svg"><script>window.CANARY=1</script></svg>',
    });
    expect(put.ok).toBe(true);
    await api()
      .post('/api/v1/agents/self/avatar-upload/complete')
      .set('Authorization', `Bearer ${c.accessToken}`)
      .expect(403);
  });
  it('MD-02 refuses a legacy private-object pointer before reading storage', async () => {
    const c = await connected();
    await ctx.dataSource.getRepository(AgentEntity).update(c.agent.id, {
      profileMetadata: {
        avatarStorageBucket: 'audit-v11',
        avatarStorageKey: 'private/other-user/canary.png',
        avatarMimeType: 'image/png',
      },
    });
    const read = jest.spyOn(ctx.app.get(AssetStorageService), 'readObject');
    await api().get(`/api/v1/agents/${c.agent.id}/avatar`).expect(404);
    expect(read).not.toHaveBeenCalled();
    read.mockRestore();
  });
  it('AV-02/AV-03 serves a legal raster with sandbox and no sniffing; upload overwrite cannot replace the approved image', async () => {
    const c = await connected();
    const up = await api()
      .post('/api/v1/agents/self/avatar-upload')
      .set('Authorization', `Bearer ${c.accessToken}`)
      .send({ fileName: 'safe.png', mimeType: 'image/png' })
      .expect(201);
    expect(
      (
        await fetch(auditBody(up.body).upload.url, {
          method: 'PUT',
          headers: { 'Content-Type': 'image/png' },
          body: onePixelPngBuffer,
        })
      ).ok,
    ).toBe(true);
    const complete = await api()
      .post('/api/v1/agents/self/avatar-upload/complete')
      .set('Authorization', `Bearer ${c.accessToken}`)
      .expect(200);
    const response = await api()
      .get(auditBody(complete.body).avatarUrl)
      .expect(200);
    expect(response.headers['x-content-type-options']).toBe('nosniff');
    expect(response.headers['content-security-policy']).toContain('sandbox');
    expect(response.headers['cache-control']).toBe('no-store');
    expect(
      (
        await fetch(auditBody(up.body).upload.url, {
          method: 'PUT',
          body: '<html>CANARY</html>',
        })
      ).ok,
    ).toBe(true);
    await api()
      .get(auditBody(complete.body).avatarUrl)
      .expect(200)
      .expect('Content-Type', 'image/png');
  });
});
