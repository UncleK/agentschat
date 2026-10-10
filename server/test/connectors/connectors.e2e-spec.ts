import { randomBytes, randomUUID, createHash } from 'node:crypto';
import request from 'supertest';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { SSEClientTransport } from '@modelcontextprotocol/sdk/client/sse.js';
import {
  createTestApplication,
  type TestApplicationContext,
  typedValue,
} from '../support/test-app';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { ConnectorRecordEntity } from '../../src/database/entities/connector-record.entity';
import { ThreadEntity } from '../../src/database/entities/thread.entity';
import { EventEntity } from '../../src/database/entities/event.entity';
import { DeliveryEntity } from '../../src/database/entities/delivery.entity';
import {
  ThreadContextType,
  ThreadVisibility,
  EventActorType,
  EventContentType,
} from '../../src/database/domain.enums';
import { FederationDeliveryService } from '../../src/modules/federation/federation-delivery.service';

describe('Universal connectors: identity, OAuth, HTTP and both MCP transports', () => {
  let ctx: TestApplicationContext;
  let base: string;
  const canonical = 'http://127.0.0.1:3310';
  const previousOrigin = process.env.CONNECTOR_PUBLIC_BASE_URL;
  beforeAll(async () => {
    process.env.CONNECTOR_PUBLIC_BASE_URL = canonical;
    ctx = await createTestApplication();
    await ctx.app.listen(0, '127.0.0.1');
    const httpServer = typedValue<import('node:http').Server>(
      ctx.app.getHttpServer(),
    );
    base =
      'http://127.0.0.1:' + (httpServer.address() as { port: number }).port;
  });
  afterAll(async () => {
    await ctx?.close();
    if (previousOrigin === undefined)
      delete process.env.CONNECTOR_PUBLIC_BASE_URL;
    else process.env.CONNECTOR_PUBLIC_BASE_URL = previousOrigin;
  });
  const joinBody = () => ({
    handle: 'connector-' + randomUUID().slice(0, 8),
    displayName: 'Connector test',
    recoveryKey: randomBytes(32).toString('hex'),
  });
  async function join() {
    const response = await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/connect')
      .send(joinBody())
      .expect(201);
    return response.body as {
      accessToken: string;
      agent: { id: string; handle: string };
    };
  }
  async function authorize(
    token: string,
    scope = 'community.read community.write community.inbox',
  ) {
    const registered = await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/oauth/register')
      .send({
        client_name: 'Test client',
        redirect_uris: ['https://client.example/callback'],
        token_endpoint_auth_method: 'none',
      })
      .expect(201);
    const client = registered.body as { client_id: string };
    const verifier = randomBytes(32).toString('base64url');
    const params = {
      client_id: client.client_id,
      response_type: 'code',
      redirect_uri: 'https://client.example/callback',
      code_challenge_method: 'S256',
      code_challenge: createHash('sha256').update(verifier).digest('base64url'),
      state: 'retain-state',
      scope,
      resource: canonical + '/api/v1/connectors/mcp',
    };
    const consent = await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/oauth/authorize')
      .query(params)
      .expect(200);
    expect(consent.headers['content-security-policy']).toContain(
      "frame-ancestors 'none'",
    );
    const ticket = consent.text.match(/name="ticket" value="([^"]+)"/)![1];
    const cookie = (
      consent.headers['set-cookie'] as unknown as string[]
    )[0].split(';')[0];
    const approved = await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/oauth/authorize')
      .set('Origin', canonical)
      .set('Cookie', cookie)
      .type('form')
      .send({ ticket, mode: 'existing', accessToken: token })
      .expect(303);
    const redirect = new URL(String(approved.headers.location));
    expect(redirect.searchParams.get('state')).toBe('retain-state');
    const exchange = {
      grant_type: 'authorization_code',
      client_id: client.client_id,
      code: redirect.searchParams.get('code'),
      code_verifier: verifier,
      redirect_uri: params.redirect_uri,
      resource: params.resource,
    };
    return { client, exchange, approved };
  }

  it('joins atomically, deduplicates concurrent lost-response retries and preserves self ownership', async () => {
    const body = joinBody();
    const results = await Promise.all(
      [1, 2, 3].map(() =>
        request(ctx.app.getHttpServer())
          .post('/api/v1/connectors/connect')
          .send(body)
          .expect(201),
      ),
    );
    const identity = results[0].body as {
      accessToken: string;
      agent: { id: string };
    };
    expect(
      results.every(
        (result) =>
          (result.body as { accessToken: string }).accessToken ===
          identity.accessToken,
      ),
    ).toBe(true);
    const agent = await ctx.dataSource
      .getRepository(AgentEntity)
      .findOneByOrFail({ id: identity.agent.id });
    expect(agent.ownerType).toBe('self');
    expect(agent.ownerUserId).toBeNull();
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/connect')
      .send({ ...body, recoveryKey: randomBytes(32).toString('hex') })
      .expect(409);
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/connect')
      .send({ ...body, displayName: 'Changed' })
      .expect(409);
    expect(
      await ctx.dataSource
        .getRepository(AgentEntity)
        .countBy({ handle: body.handle }),
    ).toBe(1);
  });

  it('cannot use a saved join key to undo credential rotation', async () => {
    const body = joinBody();
    const joined = await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/connect')
      .send(body)
      .expect(201);
    await request(ctx.app.getHttpServer())
      .post('/api/v1/agents/token/rotate')
      .set(
        'Authorization',
        'Bearer ' + (joined.body as { accessToken: string }).accessToken,
      )
      .expect(200);
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/connect')
      .send(body)
      .expect(409);
  });

  it('publishes a topic and nested replies with public verification and idempotent retries', async () => {
    const a = await join();
    const b = await join();
    const key = randomUUID();
    const contribute = (
      token: string,
      payload: unknown,
      type = 'forum.topic.create',
      id = key,
    ) =>
      request(ctx.app.getHttpServer())
        .post('/api/v1/connectors/actions')
        .set('Authorization', 'Bearer ' + token)
        .set('Idempotency-Key', id)
        .send({ type, payload })
        .expect(200);
    const payload = {
      title: 'Which public evidence verifies a connector?',
      content:
        'Two identities should exchange a sourced answer and preserve their history.',
      tags: ['connectors'],
    };
    const first = await contribute(a.accessToken, payload);
    const result = first.body as {
      verified: boolean;
      publicUrl: string;
      action: { id: string; threadId: string; eventId: string };
    };
    expect(result.verified).toBe(true);
    expect(result.publicUrl).toContain('/forum/');
    const retried = await contribute(a.accessToken, payload);
    expect((retried.body as { action: { id: string } }).action.id).toBe(
      result.action.id,
    );
    const reply = await contribute(
      b.accessToken,
      {
        threadId: result.action.threadId,
        content:
          'A successful status alone is insufficient; read the public result.',
      },
      'forum.reply.create',
      randomUUID(),
    );
    const replied = reply.body as {
      verified: boolean;
      action: { eventId: string };
    };
    expect(replied.verified).toBe(true);
    const nested = await contribute(
      a.accessToken,
      {
        threadId: result.action.threadId,
        parentEventId: replied.action.eventId,
        content: 'Agreed. This reply also checks a nested public result.',
      },
      'forum.reply.create',
      randomUUID(),
    );
    expect((nested.body as { verified: boolean }).verified).toBe(true);
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/actions')
      .set('Authorization', 'Bearer ' + a.accessToken)
      .set('Idempotency-Key', randomUUID())
      .send({ type: 'claim.confirm', payload: {} })
      .expect(400);
    await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/actions/' + result.action.id)
      .set('Authorization', 'Bearer ' + b.accessToken)
      .expect(404);
  });

  it('requires authorization for writes and rejects forged origins', async () => {
    const body = {
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: {
        name: 'participate',
        arguments: {
          type: 'forum.topic.create',
          payload: {},
          idempotencyKey: randomUUID(),
        },
      },
    };
    const denied = await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/mcp')
      .set('Accept', 'application/json, text/event-stream')
      .send(body)
      .expect(401);
    expect(denied.headers['www-authenticate']).toContain(
      'oauth-protected-resource',
    );
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/mcp')
      .set('Origin', 'https://evil.example')
      .send(body)
      .expect(403);
  });

  it('rejects invalid callbacks, plain PKCE, missing consent and wrong verifiers; consumes a code once', async () => {
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/oauth/register')
      .send({
        redirect_uris: ['https://user:password@client.example/callback'],
      })
      .expect(400);
    const a = await join();
    const authorized = await authorize(a.accessToken);
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/oauth/token')
      .type('form')
      .send({
        ...authorized.exchange,
        code_verifier: randomBytes(32).toString('base64url'),
      })
      .expect(400);
    const token = await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/oauth/token')
      .type('form')
      .send(authorized.exchange)
      .expect(200);
    expect((token.body as { access_token: string }).access_token).toMatch(
      /^ac_access\./,
    );
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/oauth/token')
      .type('form')
      .send(authorized.exchange)
      .expect(400);
    const rows = await ctx.dataSource
      .getRepository(ConnectorRecordEntity)
      .find();
    expect(JSON.stringify(rows)).not.toContain(
      (token.body as { access_token: string }).access_token,
    );
    expect(JSON.stringify(rows)).not.toContain(a.accessToken);
  });

  it('enforces scopes, rotates refresh tokens and revokes the client grant without rotating the agent', async () => {
    const a = await join();
    const { client, exchange } = await authorize(
      a.accessToken,
      'community.read',
    );
    const issued = await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/oauth/token')
      .type('form')
      .send(exchange)
      .expect(200);
    const token = issued.body as {
      access_token: string;
      refresh_token: string;
    };
    await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/policy')
      .set('Authorization', 'Bearer ' + token.access_token)
      .expect(200);
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/actions')
      .set('Authorization', 'Bearer ' + token.access_token)
      .set('Idempotency-Key', randomUUID())
      .send({ type: 'forum.topic.create', payload: {} })
      .expect(401);
    const refreshBody = {
      grant_type: 'refresh_token',
      client_id: client.client_id,
      refresh_token: token.refresh_token,
    };
    const refreshed = await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/oauth/token')
      .type('form')
      .send(refreshBody)
      .expect(200);
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/oauth/token')
      .type('form')
      .send(refreshBody)
      .expect(400);
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/oauth/revoke')
      .type('form')
      .send({
        client_id: client.client_id,
        token: (refreshed.body as { access_token: string }).access_token,
      })
      .expect(200);
    await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/policy')
      .set('Authorization', 'Bearer ' + token.access_token)
      .expect(401);
    await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/policy')
      .set('Authorization', 'Bearer ' + a.accessToken)
      .expect(200);
  });

  it('uses the official Streamable HTTP SDK client for discovery, reading and a verified contribution', async () => {
    const a = await join();
    const client = new Client({ name: 'connector-test-http', version: '1' });
    await client.connect(
      new StreamableHTTPClientTransport(
        new URL(base + '/api/v1/connectors/mcp'),
        {
          requestInit: {
            headers: { Authorization: 'Bearer ' + a.accessToken },
          },
        },
      ),
    );
    try {
      const tools = await client.listTools();
      expect(tools.tools.map((tool) => tool.name)).toContain('participate');
      const read = await client.callTool({
        name: 'browse_discussions',
        arguments: { limit: 2 },
      });
      expect(read.isError).not.toBe(true);
      const posted = await client.callTool({
        name: 'participate',
        arguments: {
          type: 'forum.topic.create',
          payload: {
            title: 'SDK interoperability',
            content:
              'This contribution was submitted by the official MCP client.',
            tags: ['connectors'],
          },
          idempotencyKey: randomUUID(),
        },
      });
      const result = (
        posted.structuredContent as { result: { verified: boolean } }
      ).result;
      expect(result.verified).toBe(true);
    } finally {
      await client.close();
    }
  });

  it('uses the official legacy SSE SDK client with the same agent identity', async () => {
    const a = await join();
    const client = new Client({ name: 'connector-test-sse', version: '1' });
    await client.connect(
      new SSEClientTransport(new URL(base + '/api/v1/connectors/sse'), {
        requestInit: { headers: { Authorization: 'Bearer ' + a.accessToken } },
        eventSourceInit: {
          fetch: (url, init) => {
            const headers = new Headers(init?.headers);
            headers.set('Authorization', 'Bearer ' + a.accessToken);
            return fetch(url, { ...init, headers });
          },
        },
      }),
    );
    try {
      const tools = await client.listTools();
      expect(tools.tools).toHaveLength(8);
      const policy = await client.callTool({
        name: 'read_my_policy',
        arguments: {},
      });
      expect(policy.isError).not.toBe(true);
    } finally {
      await client.close();
    }
  });

  it('does not read, acknowledge or consume private deliveries through the public community inbox', async () => {
    const a = await join();
    const thread = await ctx.dataSource.getRepository(ThreadEntity).save({
      contextType: ThreadContextType.DirectMessage,
      visibility: ThreadVisibility.Private,
      title: 'Private fixture',
    });
    const event = await ctx.dataSource.getRepository(EventEntity).save({
      threadId: thread.id,
      eventType: 'dm.send',
      actorType: EventActorType.Agent,
      actorAgentId: a.agent.id,
      contentType: EventContentType.Text,
      content: 'PRIVATE_FIXTURE_NOT_FOR_CONNECTOR',
      idempotencyKey: randomUUID(),
    });
    const delivery = await ctx.app
      .get(FederationDeliveryService)
      .enqueueEventForRecipient(event, a.agent.id);
    const result = await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/inbox')
      .set('Authorization', 'Bearer ' + a.accessToken)
      .expect(200);
    expect(JSON.stringify(result.body)).not.toContain(
      'PRIVATE_FIXTURE_NOT_FOR_CONNECTOR',
    );
    const saved = await ctx.dataSource
      .getRepository(DeliveryEntity)
      .findOneByOrFail({ id: delivery.id });
    expect(saved.attemptCount).toBe(0);
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/inbox/ack')
      .set('Authorization', 'Bearer ' + a.accessToken)
      .send({ deliveryIds: [delivery.id] })
      .expect(400);
  });

  it('supports a browser-only agent with persistent cookies, public publication, CSRF and private backup', async () => {
    const browser = request.agent(ctx.app.getHttpServer());
    const landing = await browser.get('/api/v1/connectors/browser').expect(200);
    const ticket = landing.text.match(/name="ticket" value="([^"]+)"/)![1];
    const handle = 'browser-' + randomUUID().slice(0, 8);
    await browser
      .post('/api/v1/connectors/browser/connect')
      .set('Origin', 'https://evil.example')
      .type('form')
      .send({ ticket, mode: 'new', handle, displayName: 'Browser fixture' })
      .expect(401);
    await browser
      .post('/api/v1/connectors/browser/connect')
      .set('Origin', canonical)
      .type('form')
      .send({ ticket, mode: 'new', handle, displayName: 'Browser fixture' })
      .expect(303);
    const welcome = await browser.get('/api/v1/connectors/browser').expect(200);
    expect(welcome.text).toContain(handle);
    const nextTicket = welcome.text.match(/name="ticket" value="([^"]+)"/)![1];
    const body = {
      ticket: nextTicket,
      type: 'forum.topic.create',
      title: 'Browser connector fixture',
      content:
        'A browser-only identity can join and verify a public contribution.',
      idempotencyKey: randomUUID(),
    };
    const published = await browser
      .post('/api/v1/connectors/browser/participate')
      .set('Origin', canonical)
      .type('form')
      .send(body)
      .expect(303);
    expect(String(published.headers.location)).toContain('/forum/');
    const duplicate = await browser
      .post('/api/v1/connectors/browser/participate')
      .set('Origin', canonical)
      .type('form')
      .send(body)
      .expect(303);
    expect(duplicate.headers.location).toBe(published.headers.location);
    const backup = await browser
      .post('/api/v1/connectors/browser/export')
      .set('Origin', canonical)
      .type('form')
      .send({ ticket: nextTicket })
      .expect(200);
    expect(backup.headers['content-disposition']).toContain('attachment');
    expect(backup.headers['cache-control']).toBe('no-store');
    const privateIdentity = backup.body as { accessToken: string };
    expect(welcome.text).not.toContain(privateIdentity.accessToken);
    await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/policy')
      .set('Authorization', 'Bearer ' + privateIdentity.accessToken)
      .expect(200);
    expect(
      await ctx.dataSource.getRepository(AgentEntity).countBy({ handle }),
    ).toBe(1);
  });
});
