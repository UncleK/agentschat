import { auditBody, type AuditResponse } from './audit-response';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import {
  createTestApplication,
  TestApplicationContext,
} from '../support/test-app';
import { FederationDeliveryService } from '../../src/modules/federation/federation-delivery.service';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import { EventOutboxService } from '../../src/modules/notifications/event-outbox.service';

describe('PF-01/PF-02 bounded delivery reads', () => {
  let ctx: TestApplicationContext;
  beforeAll(async () => {
    ctx = await createTestApplication();
    await ctx.app.get(EventOutboxService).onModuleDestroy();
  });
  afterAll(async () => {
    await ctx?.close();
  });
  async function agent() {
    const b = await request(ctx.app.getHttpServer())
      .post('/api/v1/agents/bootstrap/public')
      .send({
        handle: `query-${randomUUID().slice(0, 8)}`,
        displayName: 'Synthetic',
      })
      .expect(201);
    return (
      await request(ctx.app.getHttpServer())
        .post('/api/v1/agents/claim')
        .send({
          claimToken: auditBody(b.body).bootstrap.claimToken,
          pollingEnabled: true,
        })
        .expect(201)
    ).body as AuditResponse;
  }
  it.each([0, 1000, 100000])(
    'PF-01 uses bounded SQL with %i historical rows',
    async (count) => {
      const c = await agent();
      const threadId = randomUUID();
      await ctx.dataSource.query(
        "INSERT INTO threads(id,context_type,visibility) VALUES ($1,'dm','private')",
        [threadId],
      );
      await ctx.dataSource.query(
        `WITH inserted AS (INSERT INTO events(thread_id,event_type,actor_type) SELECT $1,'audit.history','system' FROM generate_series(1,$3::int) RETURNING id)
      INSERT INTO deliveries(event_id,recipient_agent_id,sequence,status,replay_expires_at)
      SELECT id,$2,row_number() OVER (), 'acked',now()+interval '1 day' FROM inserted`,
        [threadId, c.agent.id, count],
      );
      const log = jest.spyOn(ctx.dataSource.logger, 'logQuery');
      try {
        await ctx.app
          .get(FederationDeliveryService)
          .loadEarliestOutstandingDelivery(c.agent.id);
        const queries = log.mock.calls
          .map((args) => String(args[0]))
          .filter((q) => q.startsWith('SELECT') && q.includes('deliveries'));
        expect(queries.length).toBeGreaterThan(0);
        expect(queries.every((q) => /LIMIT 1/.test(q))).toBe(true);
        const plan = await ctx.dataSource.query<
          Array<{ 'QUERY PLAN': Array<{ Plan: { 'Actual Rows': number } }> }>
        >(
          `EXPLAIN (ANALYZE,FORMAT JSON) SELECT id FROM deliveries WHERE recipient_agent_id=$1 AND status IN ('pending','sent','retrying') ORDER BY sequence LIMIT 1`,
          [c.agent.id],
        );
        expect(plan[0]['QUERY PLAN'][0].Plan['Actual Rows']).toBe(0);
        if (count === 100000)
          expect(JSON.stringify(plan)).toContain('idx_delivery_outstanding');
      } finally {
        log.mockRestore();
      }
    },
    30000,
  );
  it('PF-02 cancels long polling and does not continue querying', async () => {
    const c = await agent();
    const principal = await ctx.app
      .get(FederationCredentialsService)
      .authenticateAgentToken(c.accessToken);
    const service = ctx.app.get(FederationDeliveryService);
    const read = jest.spyOn(
      service as unknown as {
        collectPollableDeliveries: (...args: unknown[]) => Promise<unknown>;
      },
      'collectPollableDeliveries',
    );
    const controller = new AbortController();
    const pending = service.pollDeliveries(
      principal,
      undefined,
      1,
      1,
      controller.signal,
    );
    setTimeout(() => controller.abort(), 30);
    await pending;
    const calls = read.mock.calls.length;
    await new Promise((r) => setTimeout(r, 150));
    expect(calls).toBeLessThanOrEqual(2);
    expect(read.mock.calls.length).toBe(calls);
    read.mockRestore();
  });
  it('PF-02 shares the two-poll limit across service instances and releases leases on cancel', async () => {
    const c = await agent();
    const principal = await ctx.app
      .get(FederationCredentialsService)
      .authenticateAgentToken(c.accessToken);
    const service = ctx.app.get(FederationDeliveryService);
    const second = new FederationDeliveryService(
      service['environment'],
      service['deliveryRepository'],
      service['agentConnectionRepository'],
      service['agentRepository'],
      service['eventRepository'],
      service['federationCredentialsService'],
    );
    const abort = new AbortController();
    const polls = [service, second].map((worker) =>
      worker.pollDeliveries(principal, undefined, 1, 3, abort.signal),
    );
    try {
      const until = Date.now() + 2000;
      let count = 0;
      while (count < 2 && Date.now() < until) {
        const rows = await ctx.dataSource.query<Array<{ count: string }>>(
          'SELECT count(*) FROM agent_poll_leases WHERE agent_id=$1',
          [c.agent.id],
        );
        count = Number(rows[0].count);
        if (count < 2) await new Promise((r) => setTimeout(r, 10));
      }
      expect(count).toBe(2);
      await expect(
        second.pollDeliveries(principal, undefined, 1, 0),
      ).rejects.toMatchObject({
        response: { error: { code: 'poll_concurrency_limit' } },
        status: 429,
      });
    } finally {
      abort.abort();
      await Promise.all(polls);
    }
    expect(
      await ctx.dataSource.query(
        'SELECT id FROM agent_poll_leases WHERE agent_id=$1',
        [c.agent.id],
      ),
    ).toEqual([]);
  });
});
