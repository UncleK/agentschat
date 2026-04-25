import { INestApplication } from '@nestjs/common';
import { Repository } from 'typeorm';
import { AgentDmAcceptanceMode } from '../../src/database/domain.enums';
import { EventEntity } from '../../src/database/entities/event.entity';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import { PolicyService } from '../../src/modules/policy/policy.service';
import {
  TestApplicationContext,
  createTestApplication,
  typedValue,
} from '../support/test-app';
import { createCompletedImageAsset } from '../assets/support/image-upload-test-support';
import {
  claimFederatedAgent,
  importSelfAgent,
  registerHuman,
  waitForActionStatus,
} from '../federation/support/federation-test-support';
import request from 'supertest';

describe('Content types', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let federationCredentialsService: FederationCredentialsService;
  let policyService: PolicyService;
  let eventRepository: Repository<EventEntity>;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    federationCredentialsService = app.get(FederationCredentialsService);
    policyService = app.get(PolicyService);
    eventRepository = context.dataSource.getRepository(EventEntity);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('persists text, markdown, code, and image content through canonical events', async () => {
    const sender = await importSelfAgent(app, 'types-sender', 'Types Sender');
    const recipient = await importSelfAgent(
      app,
      'types-recipient',
      'Types Recipient',
    );
    const uploader = await registerHuman(
      app,
      'types-uploader@example.com',
      'Types Uploader',
    );
    const imageAsset = await createCompletedImageAsset(
      app,
      uploader.accessToken,
    );

    await policyService.upsertAgentSafetyPolicy(recipient.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });

    const senderClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      sender.id,
      {
        pollingEnabled: true,
      },
    );

    const textAction = await submitAction(
      senderClaim.accessToken,
      'types-text',
      {
        type: 'dm.send',
        payload: {
          targetType: 'agent',
          targetId: recipient.id,
          contentType: 'text',
          content: 'Task 6 text payload.',
        },
      },
    );
    const markdownAction = await submitAction(
      senderClaim.accessToken,
      'types-markdown',
      {
        type: 'forum.topic.create',
        payload: {
          title: 'Markdown content type topic',
          tags: ['types'],
          contentType: 'markdown',
          content: '## Markdown body',
        },
      },
    );
    const codeAction = await submitAction(
      senderClaim.accessToken,
      'types-code',
      {
        type: 'forum.reply.create',
        payload: {
          threadId: markdownAction.threadId,
          parentEventId: markdownAction.eventId,
          contentType: 'code',
          content: 'const canonical = true;',
        },
      },
    );
    const imageAction = await submitAction(
      senderClaim.accessToken,
      'types-image',
      {
        type: 'dm.send',
        payload: {
          targetType: 'agent',
          targetId: recipient.id,
          contentType: 'image',
          assetId: imageAsset.asset.id,
          caption: 'Image caption from approved asset.',
        },
      },
    );

    const [textEvent, markdownEvent, codeEvent, imageEvent] = await Promise.all(
      [
        eventRepository.findOneByOrFail({ id: textAction.eventId }),
        eventRepository.findOneByOrFail({ id: markdownAction.eventId }),
        eventRepository.findOneByOrFail({ id: codeAction.eventId }),
        eventRepository.findOneByOrFail({ id: imageAction.eventId }),
      ],
    );

    expect(textEvent.contentType).toBe('text');
    expect(textEvent.assetId).toBeNull();
    expect(markdownEvent.contentType).toBe('markdown');
    expect(codeEvent.contentType).toBe('code');
    expect(imageEvent.contentType).toBe('image');
    expect(imageEvent.assetId).toBe(imageAsset.asset.id);
    expect(imageEvent.content).toBe('Image caption from approved asset.');
  });

  it('rejects invalid content type payloads before persistence', async () => {
    const sender = await importSelfAgent(app, 'types-invalid', 'Types Invalid');
    const humanRecipient = await registerHuman(
      app,
      'types-invalid-recipient@example.com',
      'Types Invalid Recipient',
    );
    const senderClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      sender.id,
      {
        pollingEnabled: true,
      },
    );

    const response = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${senderClaim.accessToken}`)
      .set('Idempotency-Key', 'types-invalid-content-type')
      .send({
        type: 'dm.send',
        payload: {
          targetType: 'human',
          targetId: humanRecipient.user.id,
          contentType: 'video',
          content: 'Should reject before persistence.',
        },
      })
      .expect(202);
    const responseBody = typedValue<{ id: string }>(response.body);

    const finalAction = await waitForActionStatus(
      app,
      senderClaim.accessToken,
      responseBody.id,
    );

    expect(finalAction.status).toBe('rejected');
    expect(finalAction.error?.message).toMatch(
      /contenttype must be text, markdown, code, image, or audio/i,
    );
  });

  async function submitAction(
    accessToken: string,
    idempotencyKey: string,
    body: {
      type: string;
      payload: Record<string, unknown>;
    },
  ) {
    const response = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${accessToken}`)
      .set('Idempotency-Key', idempotencyKey)
      .send(body)
      .expect(202);
    const responseBody = typedValue<{ id: string }>(response.body);
    const finalAction = await waitForActionStatus(
      app,
      accessToken,
      responseBody.id,
    );

    expect(finalAction.status).toBe('succeeded');

    return finalAction as {
      eventId: string;
      threadId: string;
    };
  }
});
