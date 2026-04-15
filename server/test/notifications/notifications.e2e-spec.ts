import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { SubjectType } from '../../src/database/domain.enums';
import { ContentService } from '../../src/modules/content/content.service';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import {
  TestApplicationContext,
  createTestApplication,
  typedValue,
} from '../support/test-app';

interface BellStateBody {
  hasUnread: boolean;
  unreadCount: number;
}

interface NotificationsBody {
  notifications: Array<{
    id: string;
    kind: string;
  }>;
}

interface DeliveriesBody {
  deliveries: Array<{
    event: {
      type: string;
    };
  }>;
}
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
    const sender = await registerHuman(
      app,
      'dm-sender@example.com',
      'DM Sender',
    );
    const recipient = await registerHuman(
      app,
      'dm-recipient@example.com',
      'DM Recipient',
    );
    const senderAgent = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        handle: 'notify-sender-agent',
        displayName: 'Notify Sender Agent',
      })
      .expect(201)
      .then(({ body }: { body: { id: string } }) => body);

    await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        activeAgentId: senderAgent.id,
        recipientType: 'human',
        recipientUserId: recipient.user.id,
        content: 'Hello for notifications.',
      })
      .expect(201);

    await request(app.getHttpServer())
      .get('/api/v1/notifications/bell-state')
      .set('Authorization', `Bearer ${recipient.accessToken}`)
      .expect(200)
      .expect(({ body }: { body: BellStateBody }) => {
        expect(body.hasUnread).toBe(true);
        expect(body.unreadCount).toBe(1);
      });

    const notificationsResponse = await request(app.getHttpServer())
      .get('/api/v1/notifications')
      .set('Authorization', `Bearer ${recipient.accessToken}`)
      .expect(200);
    const notificationsBody = typedValue<NotificationsBody>(
      notificationsResponse.body,
    );

    expect(notificationsBody.notifications).toHaveLength(1);
    expect(notificationsBody.notifications[0]?.kind).toBe('dm.received');

    await request(app.getHttpServer())
      .post('/api/v1/notifications/read')
      .set('Authorization', `Bearer ${recipient.accessToken}`)
      .send({
        notificationIds: [notificationsBody.notifications[0]?.id],
      })
      .expect(201)
      .expect(({ body }: { body: BellStateBody }) => {
        expect(body.hasUnread).toBe(false);
        expect(body.unreadCount).toBe(0);
      });
  });

  it('fans forum reply notifications to agent delivery polling while human topic follows stay disabled', async () => {
    const humanFollower = await registerHuman(
      app,
      'topic-follower@example.com',
      'Topic Follower',
    );
    const author = await importSelfAgent(app, 'notify-author', 'Notify Author');
    const replier = await importSelfAgent(
      app,
      'notify-replier',
      'Notify Replier',
    );
    const followerAgent = await importSelfAgent(
      app,
      'notify-follower',
      'Notify Follower',
    );
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
      .expect(403);

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
      typedValue<{ id: string }>(followActionResponse.body).id,
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

    const polledDeliveries = await request(app.getHttpServer())
      .get('/api/v1/deliveries/poll')
      .set('Authorization', `Bearer ${followerClaim.accessToken}`)
      .query({ wait_seconds: 1 })
      .expect(200);
    const polledDeliveriesBody = typedValue<DeliveriesBody>(
      polledDeliveries.body,
    );

    expect(polledDeliveriesBody.deliveries).toHaveLength(1);
    expect(polledDeliveriesBody.deliveries[0]?.event.type).toBe(
      'forum.reply.create',
    );
  });
});
