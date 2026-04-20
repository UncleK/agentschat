import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { AgentDmAcceptanceMode } from '../../src/database/domain.enums';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import { PolicyService } from '../../src/modules/policy/policy.service';
import { onePixelPngBuffer } from '../assets/support/image-upload-test-support';
import {
  TestApplicationContext,
  createTestApplication,
  typedValue,
} from '../support/test-app';
import {
  claimFederatedAgent,
  importSelfAgent,
  waitForActionStatus,
} from '../federation/support/federation-test-support';

describe('Federated agent avatars (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let federationCredentialsService: FederationCredentialsService;
  let policyService: PolicyService;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    federationCredentialsService = app.get(FederationCredentialsService);
    policyService = app.get(PolicyService);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('uploads a federated agent avatar and serves it from the public avatar endpoint', async () => {
    const agent = await importSelfAgent(
      app,
      'avatar-uploader',
      'Avatar Uploader',
    );
    const claim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      agent.id,
      {
        pollingEnabled: true,
      },
    );

    const issuedUpload = await request(app.getHttpServer())
      .post('/api/v1/agents/self/avatar-upload')
      .set('Authorization', `Bearer ${claim.accessToken}`)
      .send({
        fileName: 'agent-avatar.png',
        mimeType: 'image/png',
      })
      .expect(201);
    const issuedUploadBody = typedValue<{
      upload: {
        url: string;
        headers: {
          'Content-Type': string;
        };
      };
      avatarUrl: string;
    }>(issuedUpload.body);

    const uploadResponse = await fetch(issuedUploadBody.upload.url, {
      method: 'PUT',
      headers: {
        'Content-Type': issuedUploadBody.upload.headers['Content-Type'],
      },
      body: onePixelPngBuffer,
    });
    if (!uploadResponse.ok) {
      throw new Error(
        `Avatar presigned PUT failed with ${uploadResponse.status}: ${await uploadResponse.text()}`,
      );
    }

    const completedUpload = await request(app.getHttpServer())
      .post('/api/v1/agents/self/avatar-upload/complete')
      .set('Authorization', `Bearer ${claim.accessToken}`)
      .expect(200);
    const completedUploadBody = typedValue<{
      avatarUrl: string;
      mimeType: string;
    }>(completedUpload.body);

    expect(completedUploadBody.avatarUrl).toMatch(
      new RegExp(`/api/v1/agents/${agent.id}/avatar\\?v=`),
    );
    expect(completedUploadBody.mimeType).toBe('image/png');

    const publicAvatar = await request(app.getHttpServer())
      .get(completedUploadBody.avatarUrl)
      .buffer(true)
      .parse(binaryParser)
      .expect(200);
    const publicAvatarBody = typedValue<Buffer>(publicAvatar.body);

    expect(publicAvatar.headers['content-type']).toBe('image/png');
    expect(Buffer.compare(publicAvatarBody, onePixelPngBuffer)).toBe(0);
  });

  it('surfaces avatarEmoji on DM thread counterparts after federated profile sync', async () => {
    const sender = await importSelfAgent(app, 'emoji-sender', 'Emoji Sender');
    const recipient = await importSelfAgent(
      app,
      'emoji-recipient',
      'Emoji Recipient',
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
    const recipientClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      recipient.id,
      {
        pollingEnabled: true,
      },
    );

    const profileUpdate = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${senderClaim.accessToken}`)
      .set('Idempotency-Key', 'agent-avatar-emoji-profile')
      .send({
        type: 'agent.profile.update',
        payload: {
          avatarEmoji: '🤖',
          tags: ['federated', 'avatar'],
        },
      })
      .expect(202);
    const profileUpdateBody = typedValue<{ id: string }>(profileUpdate.body);
    const finalProfileAction = await waitForActionStatus(
      app,
      senderClaim.accessToken,
      profileUpdateBody.id,
    );
    expect(finalProfileAction.status).toBe('succeeded');

    const dmSend = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${senderClaim.accessToken}`)
      .set('Idempotency-Key', 'agent-avatar-emoji-dm')
      .send({
        type: 'dm.send',
        payload: {
          targetType: 'agent',
          targetId: recipient.id,
          contentType: 'text',
          content: 'emoji avatar sync check',
        },
      })
      .expect(202);
    const dmSendBody = typedValue<{ id: string }>(dmSend.body);
    const finalDmAction = await waitForActionStatus(
      app,
      senderClaim.accessToken,
      dmSendBody.id,
    );
    expect(finalDmAction.status).toBe('succeeded');

    const threadList = await request(app.getHttpServer())
      .get('/api/v1/content/self/dm/threads')
      .set('Authorization', `Bearer ${recipientClaim.accessToken}`)
      .expect(200);
    const threadListBody = typedValue<{
      threads: Array<{
        counterpart: {
          id: string;
          avatarUrl: string | null;
          avatarEmoji: string | null;
        };
      }>;
    }>(threadList.body);

    const senderThread = threadListBody.threads.find(
      (thread) => thread.counterpart.id === sender.id,
    );
    expect(senderThread).toBeDefined();
    expect(senderThread?.counterpart.avatarEmoji).toBe('🤖');
    expect(senderThread?.counterpart.avatarUrl).toBeNull();
  });
});

function binaryParser(
  response: NodeJS.ReadableStream,
  callback: (error: Error | null, body?: Buffer) => void,
) {
  const chunks: Buffer[] = [];
  response.on('data', (chunk) => {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  });
  response.on('end', () => callback(null, Buffer.concat(chunks)));
  response.on('error', (error) => callback(error));
}
