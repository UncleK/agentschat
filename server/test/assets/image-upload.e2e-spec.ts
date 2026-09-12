import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { Repository } from 'typeorm';
import { EventEntity } from '../../src/database/entities/event.entity';
import {
  TestApplicationContext,
  createTestApplication,
  typedValue,
} from '../support/test-app';
import {
  completeUpload,
  createCompletedImageAsset,
  issueUpload,
  putIssuedUpload,
} from './support/image-upload-test-support';

describe('Image upload flow (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let eventRepository: Repository<EventEntity>;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    eventRepository = context.dataSource.getRepository(EventEntity);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('issues, uploads, completes, moderates, and attaches an approved image asset', async () => {
    const sender = await registerHuman(
      'asset-sender@example.com',
      'Asset Sender',
    );
    const recipient = await registerHuman(
      'asset-recipient@example.com',
      'Asset Recipient',
    );
    const senderAgent = await importHumanOwnedAgent(
      sender.accessToken,
      'asset-sender-agent',
      'Asset Sender Agent',
    );
    const completedAsset = await createCompletedImageAsset(
      app,
      sender.accessToken,
    );

    expect(completedAsset.asset.uploadStatus).toBe('uploaded');
    expect(completedAsset.asset.moderationStatus).toBe('approved');

    const response = await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        activeAgentId: senderAgent.id,
        recipientType: 'human',
        recipientUserId: recipient.user.id,
        contentType: 'image',
        assetId: completedAsset.asset.id,
        caption: 'Approved upload attached to a DM.',
      })
      .expect(201);
    const responseBody = typedValue<{
      eventId: string;
    }>(response.body);

    const storedEvent = await eventRepository.findOneByOrFail({
      id: responseBody.eventId,
    });

    expect(storedEvent.contentType).toBe('image');
    expect(storedEvent.assetId).toBe(completedAsset.asset.id);
    expect(storedEvent.content).toBe('Approved upload attached to a DM.');
  });

  it('blocks moderated image rejections from becoming visible content', async () => {
    const sender = await registerHuman(
      'rejected-sender@example.com',
      'Rejected Sender',
    );
    const recipient = await registerHuman(
      'rejected-recipient@example.com',
      'Rejected Recipient',
    );
    const senderAgent = await importHumanOwnedAgent(
      sender.accessToken,
      'rejected-sender-agent',
      'Rejected Sender Agent',
    );
    const upload = await issueUpload(app, sender.accessToken, {
      fileName: 'nsfw-scene.png',
    });

    await putIssuedUpload(upload.upload);

    const rejectedAsset = await completeUpload(
      app,
      sender.accessToken,
      upload.asset.id,
    );

    expect(rejectedAsset.moderationStatus).toBe('rejected');

    await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        activeAgentId: senderAgent.id,
        recipientType: 'human',
        recipientUserId: recipient.user.id,
        contentType: 'image',
        assetId: upload.asset.id,
        caption: 'This should never become visible.',
      })
      .expect(403)
      .expect(({ body }: { body: { message: string } }) => {
        expect(body.message).toMatch(/rejected assets cannot be attached/i);
      });
  });

  it('accepts direct authenticated image uploads through the API', async () => {
    const sender = await registerHuman(
      'direct-upload-sender@example.com',
      'Direct Upload Sender',
    );

    const response = await request(app.getHttpServer())
      .post('/api/v1/assets/images')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .field('fileName', 'camera-shot.png')
      .field('mimeType', 'image/png')
      .attach('file', Buffer.from('fake-png-payload'), 'camera-shot.png')
      .expect(201);

    const body = response.body as {
      id: string;
      kind: string;
      uploadStatus: string;
      moderationStatus: string;
      url: string;
    };
    expect(body.id).toBeTruthy();
    expect(body.kind).toBe('image');
    expect(body.uploadStatus).toBe('uploaded');
    expect(body.moderationStatus).toBe('approved');
    expect(body.url).toBe(`/api/v1/assets/${body.id}/content`);
  });

  it.each([
    ['image', '/api/v1/assets/images'],
    [
      'voice',
      '/api/v1/content/dm/threads/00000000-0000-4000-8000-000000000001/voice',
    ],
  ])(
    'rejects oversized multipart parsing for %s uploads',
    async (kind, url) => {
      const sender = await registerHuman(
        `bounded-${kind}@example.com`,
        'Bounded Upload Sender',
      );

      for (const field of ['metadata[x][x][x][x][x]', 'metadata[17]']) {
        await request(app.getHttpServer())
          .post(url)
          .set('Authorization', `Bearer ${sender.accessToken}`)
          .field(field, 'invalid')
          .attach('file', Buffer.from('fixture'), 'fixture.bin')
          .expect(400);
      }

      const tooManyFields = request(app.getHttpServer())
        .post(url)
        .set('Authorization', `Bearer ${sender.accessToken}`);
      for (let index = 0; index < 17; index += 1) {
        tooManyFields.field(`field${index}`, 'value');
      }
      await tooManyFields
        .attach('file', Buffer.from('fixture'), 'fixture.bin')
        .expect(400);

      await request(app.getHttpServer())
        .post(url)
        .set('Authorization', `Bearer ${sender.accessToken}`)
        .attach('file', Buffer.alloc(10 * 1024 * 1024 + 1), 'oversized.bin')
        .expect(413);

      await request(app.getHttpServer())
        .get('/api/v1/public/index?type=agents&limit=1')
        .expect(200);
    },
  );
  async function registerHuman(email: string, displayName: string) {
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/register/email')
      .send({
        email,
        username: buildUsername(email),
        displayName,
        password: 'password123',
      })
      .expect(201);

    return response.body as {
      accessToken: string;
      user: {
        id: string;
        email: string;
      };
    };
  }

  async function importHumanOwnedAgent(
    accessToken: string,
    handle: string,
    displayName: string,
  ) {
    const response = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        handle,
        displayName,
      })
      .expect(201);

    return response.body as {
      id: string;
    };
  }

  function buildUsername(email: string): string {
    return (
      email
        .trim()
        .toLowerCase()
        .split('@')[0]
        ?.replace(/[^a-z0-9]+/g, '_')
        .replace(/^_+|_+$/g, '')
        .slice(0, 24) || 'human_user'
    );
  }
});
