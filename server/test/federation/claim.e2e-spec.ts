import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { Repository } from 'typeorm';
import { AgentStatus } from '../../src/database/domain.enums';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
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

describe('Federation claim transport (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let federationCredentialsService: FederationCredentialsService;
  let agentRepository: Repository<AgentEntity>;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    federationCredentialsService = app.get(FederationCredentialsService);
    agentRepository = context.dataSource.getRepository(AgentEntity);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('claims an agent connection, returns transport credentials, and rotates tokens', async () => {
    const agent = await importSelfAgent(
      app,
      'federation-claim-agent',
      'Federation Claim Agent',
    );
    const claimResponse = await claimFederatedAgent(
      app,
      federationCredentialsService,
      agent.id,
      {
        transportMode: 'hybrid',
        webhookUrl: 'https://example.test/hooks/agent',
        pollingEnabled: true,
        capabilities: {
          actions: ['dm.send'],
        },
      },
    );

    expect(claimResponse.agent.handle).toBe('federation-claim-agent');
    expect(claimResponse.transport.mode).toBe('hybrid');
    expect(claimResponse.transport.webhook?.signingSecret).toEqual(
      expect.any(String),
    );
    expect(claimResponse.transport.polling.enabled).toBe(true);
    expect(claimResponse.accessToken).toEqual(expect.any(String));

    const rotateResponse = await request(app.getHttpServer())
      .post('/api/v1/agents/token/rotate')
      .set('Authorization', `Bearer ${claimResponse.accessToken}`)
      .expect(200);
    const rotateResponseBody = typedValue<{ accessToken: string }>(
      rotateResponse.body,
    );

    expect(rotateResponseBody.accessToken).toEqual(expect.any(String));
    expect(rotateResponseBody.accessToken).not.toBe(claimResponse.accessToken);

    await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${claimResponse.accessToken}`)
      .set('Idempotency-Key', 'claim-old-token')
      .send({
        type: 'agent.profile.update',
        payload: {
          displayName: 'Should Fail With Old Token',
        },
      })
      .expect(401)
      .expect(({ body }: { body: { error: { code: string } } }) => {
        expect(body.error.code).toBe('invalid_agent_token');
      });

    const rotatedAction = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${rotateResponseBody.accessToken}`)
      .set('Idempotency-Key', 'claim-new-token')
      .send({
        type: 'agent.profile.update',
        payload: {
          displayName: 'Rotated Name',
          vendorName: 'OpenClaw',
          runtimeName: 'OpenClaw Main',
        },
      })
      .expect(202);
    const rotatedActionBody = typedValue<{ id: string }>(rotatedAction.body);

    const finalAction = await waitForActionStatus(
      app,
      rotateResponseBody.accessToken,
      rotatedActionBody.id,
    );

    expect(finalAction.status).toBe('succeeded');

    await expect(
      agentRepository.findOneByOrFail({ id: agent.id }),
    ).resolves.toMatchObject({
      displayName: 'Rotated Name',
      vendorName: 'OpenClaw',
      runtimeName: 'OpenClaw Main',
      status: AgentStatus.Online,
    });
  });

  it('returns the standard federation error shape for invalid claim tokens', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/agents/claim')
      .send({
        claimToken: 'not-a-real-token',
        pollingEnabled: true,
      })
      .expect(401)
      .expect(
        ({ body }: { body: { error: { code: string; message: string } } }) => {
          expect(body.error.code).toBe('invalid_claim_token');
          expect(body.error.message).toMatch(/claim token/i);
        },
      );
  });
});
