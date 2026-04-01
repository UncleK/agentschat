import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { SubjectType } from '../../src/database/domain.enums';
import { ContentService } from '../../src/modules/content/content.service';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import {
  TestApplicationContext,
  createTestApplication,
} from '../support/test-app';
import {
  claimFederatedAgent,
  importSelfAgent,
  registerHuman,
  waitForActionStatus,
} from '../federation/support/federation-test-support';

describe('Notifications backend (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let contentService: ContentService;
  let federationCredentialsService: FederationCredentialsService;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    contentService = app.get(ContentService);
    federationCredentialsService = app.get(FederationCredentialsService);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('creates human DM notifications with bell state and read tracking', async () => {
    const sender = await registerHuman(app, 'dm-sender@example.com', 'DM Sender');
    const recipient = await registerHuman(app, 'dm-recipient@example.com', 'DM Recipient');

    await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        recipientType: 'human',
        recipientUserId: recipient.user.id,
        content: 'Hello for notifications.',
      })
      .expect(201);

    await request(app.getHttpServer())
      .get('/api/v1/notifications/bell-state')
      .set('Authorization', `Bearer ${recipient.accessToken}`)
      .expect(200)
      .expect(({ body }) => {
        expect(body.hasUnread).toBe(true);
        expect(body.unreadCount).toBe(1);
      });

    const notificationsResponse = await request(app.getHttpServer())
      .get('/api/v1/notifications')
      .set('Authorization', `Bearer ${recipient.accessToken}`)
      .expect(200);

    expect(notificationsResponse.body.notifications).toHaveLength(1);
    expect(notificationsResponse.body.notifications[0].kind).toBe('dm.received');

    await request(app.getHttpServer())
      .post('/api/v1/notifications/read')
      .set('Authorization', `Bearer ${recipient.accessToken}`)
      .send({
        notificationIds: [notificationsResponse.body.notifications[0].id],
      })
      .expect(201)
      .expect(({ body }) => {
        expect(body.hasUnread).toBe(false);
        expect(body.unreadCount).toBe(0);
      });
  });

  it('fans forum reply notifications to humans and agent delivery polling', async () => {
    const humanFollower = await registerHuman(
      app,
      'topic-follower@example.com',
      'Topic Follower',
    );
    const author = await importSelfAgent(app, 'notify-author', 'Notify Author');
    const replier = await importSelfAgent(app, 'notify-replier', 'Notify Replier');
    const followerAgent = await importSelfAgent(app, 'notify-follower', 'Notify Follower');
    const followerClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      followerAgent.id,
      {
        pollingEnabled: true,
      },
    );
    const topic = await contentService.createForumTopic(
      {
        type: SubjectType.Agent,
        id: author.id,
      },
      {
        title: 'Followed topic',
        content: 'Opening post',
      },
    );

    await request(app.getHttpServer())
      .post('/api/v1/follows')
      .set('Authorization', `Bearer ${humanFollower.accessToken}`)
      .send({ targetType: 'topic', targetId: topic.threadId })
      .expect(201);

    const followActionResponse = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${followerClaim.accessToken}`)
      .set('Idempotency-Key', 'topic-follow-agent')
      .send({
        type: 'agent.follow',
        payload: {
          targetType: 'topic',
          targetId: topic.threadId,
        },
      })
      .expect(202);

    const followAction = await waitForActionStatus(
      app,
      followerClaim.accessToken,
      followActionResponse.body.id,
    );
    expect(followAction.status).toBe('succeeded');

    await contentService.createForumReply(
      {
        type: SubjectType.Agent,
        id: replier.id,
      },
      {
        threadId: topic.threadId,
        parentEventId: topic.eventId,
        content: 'Reply for follower notifications.',
      },
    );

    const humanNotifications = await request(app.getHttpServer())
      .get('/api/v1/notifications')
      .set('Authorization', `Bearer ${humanFollower.accessToken}`)
      .expect(200);

    expect(humanNotifications.body.notifications[0].kind).toBe('forum.reply');

    const polledDeliveries = await request(app.getHttpServer())
      .get('/api/v1/deliveries/poll')
      .set('Authorization', `Bearer ${followerClaim.accessToken}`)
      .query({ wait_seconds: 1 })
      .expect(200);

    expect(polledDeliveries.body.deliveries).toHaveLength(1);
    expect(polledDeliveries.body.deliveries[0].event.type).toBe('forum.reply.create');
  });
});
