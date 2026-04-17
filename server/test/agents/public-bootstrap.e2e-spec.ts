import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { Repository } from 'typeorm';
import { AgentStatus } from '../../src/database/domain.enums';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import {
  TestApplicationContext,
  createTestApplication,
  typedValue,
} from '../support/test-app';

interface PublicBootstrapResponse {
  bootstrap: {
    protocolVersion: string;
    claimToken: string;
    expiresAt: string;
    code: string;
    bootstrapPath: string;
    agent: {
      id: string;
      handle: string;
      displayName: string;
      ownerType: string;
    };
    transport: {
      claimPath: string;
      actionsPath: string;
      pollingPath: string;
      acksPath: string;
    };
  };
}

interface AgentBootstrapResponse {
  protocolVersion: string;
  claimToken: string;
  agent: {
    id: string;
    handle: string;
    displayName: string;
    ownerType: string;
  };
}

interface ClaimAgentResponse {
  accessToken: string;
  agent: {
    id: string;
    handle: string;
  };
  transport: {
    mode: string;
    polling: {
      enabled: boolean;
    };
  };
}

describe('Agent public bootstrap (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let agentRepository: Repository<AgentEntity>;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    agentRepository = context.dataSource.getRepository(AgentEntity);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('creates a public self-owned bootstrap payload that can be claimed directly by a runtime', async () => {
    const bootstrapResponse = await request(app.getHttpServer())
      .post('/api/v1/agents/bootstrap/public')
      .send({
        handle: 'public-bootstrap-agent',
        displayName: 'Public Bootstrap Agent',
      })
      .expect(201);
    const bootstrapBody = typedValue<PublicBootstrapResponse>(
      bootstrapResponse.body,
    );

    expect(bootstrapBody.bootstrap.protocolVersion).toBe('v1');
    expect(typeof bootstrapBody.bootstrap.code).toBe('string');
    expect(typeof bootstrapBody.bootstrap.expiresAt).toBe('string');
    expect(bootstrapBody.bootstrap.bootstrapPath).toContain(
      '/api/v1/agents/bootstrap?claimToken=',
    );
    expect(bootstrapBody.bootstrap.agent).toEqual({
      id: bootstrapBody.bootstrap.agent.id,
      handle: 'public-bootstrap-agent',
      displayName: 'Public Bootstrap Agent',
      ownerType: 'self',
    });
    expect(bootstrapBody.bootstrap.transport).toEqual({
      claimPath: '/api/v1/agents/claim',
      actionsPath: '/api/v1/actions',
      pollingPath: '/api/v1/deliveries/poll',
      acksPath: '/api/v1/acks',
    });
    expect(bootstrapBody.bootstrap.bootstrapPath).toContain(
      encodeURIComponent(bootstrapBody.bootstrap.claimToken),
    );

    const readBootstrapResponse = await request(app.getHttpServer())
      .get('/api/v1/agents/bootstrap')
      .query({
        claimToken: bootstrapBody.bootstrap.claimToken,
      })
      .expect(200);
    const readBootstrapBody = typedValue<AgentBootstrapResponse>(
      readBootstrapResponse.body,
    );

    expect(readBootstrapBody.protocolVersion).toBe('v1');
    expect(readBootstrapBody.claimToken).toBe(
      bootstrapBody.bootstrap.claimToken,
    );
    expect(readBootstrapBody.agent).toEqual({
      id: bootstrapBody.bootstrap.agent.id,
      handle: 'public-bootstrap-agent',
      displayName: 'Public Bootstrap Agent',
      ownerType: 'self',
    });

    const claimResponse = await request(app.getHttpServer())
      .post('/api/v1/agents/claim')
      .send({
        claimToken: bootstrapBody.bootstrap.claimToken,
        pollingEnabled: true,
      })
      .expect(201);
    const claimBody = typedValue<ClaimAgentResponse>(claimResponse.body);

    expect(typeof claimBody.accessToken).toBe('string');
    expect(claimBody.agent).toMatchObject({
      id: bootstrapBody.bootstrap.agent.id,
      handle: 'public-bootstrap-agent',
    });
    expect(claimBody.transport).toMatchObject({
      mode: 'polling',
      polling: {
        enabled: true,
      },
    });

    await expect(
      agentRepository.findOneByOrFail({
        id: bootstrapBody.bootstrap.agent.id,
      }),
    ).resolves.toMatchObject({
      status: AgentStatus.Online,
    });
  });
});
