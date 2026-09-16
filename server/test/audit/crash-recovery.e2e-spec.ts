import { auditBody } from './audit-response';
import { fork, ChildProcess } from 'node:child_process';
import { resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import {
  createTestApplication,
  TestApplicationContext,
} from '../support/test-app';
import { FederationService } from '../../src/modules/federation/federation.service';
import { FederationActionEntity } from '../../src/database/entities/federation-action.entity';
import { EventEntity } from '../../src/database/entities/event.entity';
import { FederationActionStatus } from '../../src/database/domain.enums';
import { waitForActionStatus } from '../federation/support/federation-test-support';

describe('AQ-01/AQ-02/AQ-03 real process kill and restart', () => {
  let ctx: TestApplicationContext;
  const children = new Set<ChildProcess>();
  beforeAll(async () => {
    ctx = await createTestApplication();
    await ctx.app.get(FederationService).onModuleDestroy();
  });
  afterAll(async () => {
    for (const child of children) await kill(child);
    await ctx?.close();
  });
  async function kill(child: ChildProcess) {
    if (child.exitCode !== null || child.signalCode !== null) return;
    await new Promise<void>((resolve) => {
      child.once('exit', () => resolve());
      child.kill('SIGKILL');
    });
    children.delete(child);
  }
  function spawn(mode: string, id: string) {
    const child = fork(resolve(__dirname, 'fault-worker.cjs'), [], {
      cwd: resolve(__dirname, '../..'),
      env: {
        ...process.env,
        DATABASE_URL: String(ctx.dataSource.options.url),
        AUDIT_FAULT_MODE: mode,
        AUDIT_TARGET_ACTION: id,
      },
      stdio: ['ignore', 'ignore', 'pipe', 'ipc'],
    });
    children.add(child);
    const seen = new Set<string>();
    let error = '';
    child.stderr?.on('data', () => undefined);
    child.on('message', (message: { phase?: string; error?: string }) => {
      if (message.phase) seen.add(message.phase);
      error ||= message.error ?? '';
    });
    return {
      child,
      wait: async (phase: string) => {
        const until = Date.now() + 15000;
        while (
          !seen.has(phase) &&
          Date.now() < until &&
          !error &&
          child.exitCode === null
        )
          await new Promise((r) => setTimeout(r, 25));
        if (error || !seen.has(phase))
          throw new Error(
            `Child did not reach ${phase}: ${error || child.exitCode}`,
          );
      },
    };
  }
  it.each(['accepted', 'processing', 'after-effect'])(
    'recovers %s kill exactly once',
    async (mode) => {
      const b = await request(ctx.app.getHttpServer())
        .post('/api/v1/agents/bootstrap/public')
        .send({
          handle: `kill-${randomUUID().slice(0, 8)}`,
          displayName: 'Synthetic crash agent',
        })
        .expect(201);
      const c = await request(ctx.app.getHttpServer())
        .post('/api/v1/agents/claim')
        .send({
          claimToken: auditBody(b.body).bootstrap.claimToken,
          pollingEnabled: true,
        })
        .expect(201);
      const repo = ctx.dataSource.getRepository(FederationActionEntity);
      const action = await repo.save(
        repo.create({
          agentId: auditBody(c.body).agent.id,
          actionType: 'forum.topic.create',
          status: FederationActionStatus.Accepted,
          idempotencyKey: randomUUID(),
          requestHash: 'synthetic',
          payload: {
            title: 'Crash recovery canary',
            content: 'No real user data',
          },
        }),
      );
      const first = spawn(mode, action.id);
      await first.wait(mode);
      await kill(first.child);
      // Simulate passage of lease time after the OS kill; never steal a live lease.
      await ctx.dataSource.query(
        "UPDATE federation_actions SET lease_expires_at=now()-interval '1 second' WHERE id=$1",
        [action.id],
      );
      const next = spawn('recover', action.id);
      await next.wait('ready');
      const final = await waitForActionStatus(
        ctx.app,
        auditBody(c.body).accessToken,
        action.id,
        ['succeeded'],
        5000,
      );
      expect(final.eventId).toBeTruthy();
      expect(
        await ctx.dataSource.getRepository(EventEntity).countBy({
          actorAgentId: auditBody(c.body).agent.id,
          eventType: 'forum.topic.create',
        }),
      ).toBe(1);
      await kill(next.child);
    },
    45000,
  );
});
