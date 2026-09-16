import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { createServer } from 'node:http';
import request from 'supertest';
import {
  createTestApplication,
  TestApplicationContext,
  typedValue,
} from '../support/test-app';
import { auditBody } from './audit-response';
import { registerHuman } from '../federation/support/federation-test-support';

describe('RR2-05/RR3 actual Python process against isolated HTTP backend', () => {
  let ctx: TestApplicationContext, base: string, root: string;
  const run = promisify(execFile);
  const adapter = resolve(
    __dirname,
    '../../../skills/agents-chat-v1/adapter/launch.py',
  );
  beforeAll(async () => {
    ctx = await createTestApplication();
    await ctx.app.listen(0, '127.0.0.1');
    base = await ctx.app.getUrl();
    root = await mkdtemp(join(tmpdir(), 'agentschat-reaudit-'));
  });
  afterAll(async () => {
    await ctx?.close();
    if (root) await rm(root, { recursive: true, force: true });
  });
  async function cli(mode: string, slot: string, extra: string[] = []) {
    return run(
      process.env.STT_PYTHON_BIN || 'python',
      [
        adapter,
        '--mode',
        mode,
        '--slot',
        slot,
        '--state-dir',
        join(root, slot),
        '--server-base-url',
        base,
        '--skip-poll',
        ...extra,
      ],
      {
        timeout: 30000,
        env: {
          ...process.env,
          PYTHONDONTWRITEBYTECODE: '1',
          NO_PROXY: 'localhost,127.0.0.1,::1',
        },
      },
    );
  }
  async function state(slot: string) {
    return typedValue<{
      agentId: string;
      accessToken: string;
      pendingBootstrap?: unknown;
    }>(JSON.parse(await readFile(join(root, slot, 'state.json'), 'utf8')));
  }
  it.each(['public', 'bound'])(
    'RR2-05 %s restart reuses identity and bearer without reinitializing',
    async (mode) => {
      const slot = `process-${mode}`;
      let extra: string[] = [];
      if (mode === 'bound') {
        const h = await registerHuman(
          ctx.app,
          `${randomUUID()}@example.test`,
          'Bound owner',
        );
        const invitation = auditBody(
          (
            await request(ctx.app.getHttpServer())
              .post('/api/v1/agents/import/human/invitations')
              .set('Authorization', `Bearer ${h.accessToken}`)
              .expect(201)
          ).body,
        );
        extra = ['--claim-token', invitation.invitation.claimToken];
      }
      await cli(mode, slot, extra);
      const before = await state(slot);
      expect(before.pendingBootstrap).toBeUndefined();
      await cli(mode, slot, extra);
      const after = await state(slot);
      expect(after.agentId).toBe(before.agentId);
      expect(after.accessToken).toBe(before.accessToken);
      const action = await cli(mode, slot, [
        ...extra,
        '--submit-action-json',
        JSON.stringify({
          type: 'forum.topic.create',
          payload: {
            title: 'Python process continuity',
            content: 'Synthetic process participation',
          },
        }),
        '--wait-action',
      ]);
      expect(action.stdout).toContain('succeeded');
    },
  );
  it('RR3-02 stdin pipe cannot authorize binding or even create a device request', async () => {
    const c = await state('process-public');
    const h = await registerHuman(
      ctx.app,
      `${randomUUID()}@example.test`,
      'Later owner',
    );
    const binding = auditBody(
      (
        await request(ctx.app.getHttpServer())
          .post('/api/v1/agents/claim-requests')
          .set('Authorization', `Bearer ${h.accessToken}`)
          .expect(201)
      ).body,
    );
    await expect(
      cli('claim', 'process-public', [
        '--agent-id',
        c.agentId,
        '--claim-request-id',
        binding.claimRequest.id,
        '--challenge-token',
        binding.challengeToken,
      ]),
    ).rejects.toThrow(/interactive original-controller terminal/);
    const rows = await ctx.dataSource.query<Array<{ count: string }>>(
      'SELECT count(*) FROM binding_devices WHERE request_id=$1',
      [binding.claimRequest.id],
    );
    expect(rows[0].count).toBe('0');
  });
  it('RR2-01 native launcher resumes a genuinely lost HTTP response from persisted proof without a new identity', async () => {
    const driver = resolve(__dirname, 'native-recovery-client.mjs');
    const stateDir = join(root, 'native');
    await run(process.execPath, [driver, base, stateDir, 'lose-response'], {
      timeout: 30000,
    });
    await run(process.execPath, [driver, base, stateDir, 'resume'], {
      timeout: 30000,
    });
    const saved = typedValue<{
      agentId: string;
      accessToken: string;
      pendingBootstrap?: unknown;
    }>(JSON.parse(await readFile(join(stateDir, 'state.json'), 'utf8')));
    expect(saved.pendingBootstrap).toBeUndefined();
    await request(ctx.app.getHttpServer())
      .get('/api/v1/agents/self/safety-policy')
      .set('Authorization', `Bearer ${saved.accessToken}`)
      .expect(200);
    const rows = await ctx.dataSource.query<Array<{ count: string }>>(
      "SELECT count(*) FROM agents WHERE handle='native-recovery-probe'",
    );
    expect(rows[0].count).toBe('1');
  });
  it('RR2-03 Python accepts an authorized recovery invitation for its existing identity after disconnect', async () => {
    const slot = 'process-recovery';
    const h = await registerHuman(
      ctx.app,
      `${randomUUID()}@example.test`,
      'Recovery owner',
    );
    const invite = auditBody(
      (
        await request(ctx.app.getHttpServer())
          .post('/api/v1/agents/import/human/invitations')
          .set('Authorization', `Bearer ${h.accessToken}`)
          .expect(201)
      ).body,
    );
    await cli('bound', slot, ['--claim-token', invite.invitation.claimToken]);
    const before = await state(slot);
    await request(ctx.app.getHttpServer())
      .post('/api/v1/agents/connections/disconnect-all')
      .set('Authorization', `Bearer ${h.accessToken}`)
      .expect(200);
    const fresh = auditBody(
      (
        await request(ctx.app.getHttpServer())
          .post(`/api/v1/agents/${before.agentId}/connection-invitation`)
          .set('Authorization', `Bearer ${h.accessToken}`)
          .expect(201)
      ).body,
    );
    await cli('bound', slot, ['--claim-token', fresh.invitation.claimToken]);
    const after = await state(slot);
    expect(after.agentId).toBe(before.agentId);
    expect(after.accessToken).not.toBe(before.accessToken);
    await cli('bound', slot, ['--claim-token', fresh.invitation.claimToken]);
    expect((await state(slot)).accessToken).toBe(after.accessToken);
  });
  it('RR4 Python credential-bearing requests refuse redirects without forwarding credentials', async () => {
    let forwarded = 0;
    const sink = createServer((_req, res) => {
      forwarded++;
      res.end('{}');
    });
    await new Promise<void>((resolve) => sink.listen(0, '127.0.0.1', resolve));
    const target = sink.address();
    if (!target || typeof target === 'string')
      throw new Error('Missing loopback port');
    const origin = createServer((_req, res) => {
      res.writeHead(302, { Location: `http://127.0.0.1:${target.port}/sink` });
      res.end();
    });
    await new Promise<void>((resolve) =>
      origin.listen(0, '127.0.0.1', resolve),
    );
    const source = origin.address();
    if (!source || typeof source === 'string')
      throw new Error('Missing loopback port');
    try {
      const probe = `import sys; sys.path.insert(0, sys.argv[1]); import launch; launch.http_json('GET', sys.argv[2], access_token='synthetic-control-proof')`;
      await expect(
        run(
          process.env.STT_PYTHON_BIN || 'python',
          [
            '-c',
            probe,
            resolve(adapter, '..'),
            `http://127.0.0.1:${source.port}/start`,
          ],
          {
            env: {
              ...process.env,
              PYTHONDONTWRITEBYTECODE: '1',
              NO_PROXY: '127.0.0.1',
            },
          },
        ),
      ).rejects.toThrow(/HTTP 302/);
      expect(forwarded).toBe(0);
    } finally {
      await Promise.all([
        new Promise<void>((resolve) => origin.close(() => resolve())),
        new Promise<void>((resolve) => sink.close(() => resolve())),
      ]);
    }
  });
});
