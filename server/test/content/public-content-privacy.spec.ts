import { randomUUID } from 'node:crypto';
import { NotFoundException } from '@nestjs/common';
import request from 'supertest';
import {
  AgentOwnerType,
  AgentDmAcceptanceMode,
  AgentStatus,
  AssetKind,
  AssetModerationStatus,
  AssetUploadStatus,
  AuthProvider,
  EventActorType,
  EventContentType,
  SubjectType,
  ThreadContextType,
  ThreadVisibility,
} from '../../src/database/domain.enums';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { AssetEntity } from '../../src/database/entities/asset.entity';
import { DebateSessionEntity } from '../../src/database/entities/debate-session.entity';
import { EventEntity } from '../../src/database/entities/event.entity';
import { ForumTopicViewEntity } from '../../src/database/entities/forum-topic-view.entity';
import { ThreadEntity } from '../../src/database/entities/thread.entity';
import { ThreadParticipantEntity } from '../../src/database/entities/thread-participant.entity';
import { UserEntity } from '../../src/database/entities/user.entity';
import { AgentsService } from '../../src/modules/agents/agents.service';
import { AssetStorageService } from '../../src/modules/assets/asset-storage.service';
import { AssetsService } from '../../src/modules/assets/assets.service';
import { AuthService } from '../../src/modules/auth/auth.service';
import { ContentService } from '../../src/modules/content/content.service';
import { DebateService } from '../../src/modules/debate/debate.service';
import { ModerationService } from '../../src/modules/moderation/moderation.service';
import { PublicIndexService } from '../../src/modules/public/public-index.service';
import { PolicyService } from '../../src/modules/policy/policy.service';
import {
  TestApplicationContext,
  createTestApplication,
} from '../support/test-app';

describe('Public content and attachment privacy', () => {
  let context: TestApplicationContext;
  let content: ContentService;

  beforeAll(async () => {
    context = await createTestApplication();
    content = context.app.get(ContentService);
    jest
      .spyOn(context.app.get(AssetStorageService), 'readObject')
      .mockResolvedValue({
        body: Buffer.from('private image'),
        byteSize: 13,
        mimeType: 'image/png',
      });
  });

  afterAll(async () => {
    await context?.close();
  });

  async function createUser() {
    const repository = context.dataSource.getRepository(UserEntity);
    const id = randomUUID();
    return repository.save(
      repository.create({
        email: `${id}@example.com`,
        username: id.replace(/-/g, '').slice(0, 20),
        displayName: 'Privacy test human',
        authProvider: AuthProvider.Email,
      }),
    );
  }

  async function createAgent(ownerUserId?: string) {
    const repository = context.dataSource.getRepository(AgentEntity);
    return repository.save(
      repository.create({
        handle: `privacy-${randomUUID()}`,
        displayName: 'Privacy test agent',
        ownerType: ownerUserId ? AgentOwnerType.Human : AgentOwnerType.Self,
        ownerUserId: ownerUserId ?? null,
        status: AgentStatus.Online,
      }),
    );
  }

  async function createTopic(
    visibility = ThreadVisibility.Public,
    metadata = {},
  ) {
    const threads = context.dataSource.getRepository(ThreadEntity);
    const events = context.dataSource.getRepository(EventEntity);
    const topics = context.dataSource.getRepository(ForumTopicViewEntity);
    const thread = await threads.save(
      threads.create({
        contextType: ThreadContextType.ForumTopic,
        visibility,
        metadata,
      }),
    );
    const root = await events.save(
      events.create({
        threadId: thread.id,
        eventType: 'forum.topic.create',
        actorType: EventActorType.System,
        contentType: EventContentType.Text,
        content: 'Public body',
      }),
    );
    await topics.save(
      topics.create({
        threadId: thread.id,
        rootEventId: root.id,
        title: `Topic ${thread.id}`,
        lastActivityAt: new Date(),
      }),
    );
    return { thread, root };
  }

  it('filters private and moderated threads before applying the public listing limit', async () => {
    const visible = await createTopic();
    const privateTopic = await createTopic(ThreadVisibility.Private);
    const hidden = await createTopic(ThreadVisibility.Public, {
      moderation: { hidden: true },
    });
    const deleted = await createTopic(ThreadVisibility.Public, {
      moderation: { deleted: true },
    });
    const result = await content.listPublicForumTopics({ limit: '1' });
    expect(result.topics.map((topic) => topic.threadId)).toEqual([
      visible.thread.id,
    ]);
    for (const topic of [privateTopic, hidden, deleted]) {
      await request(context.app.getHttpServer())
        .get(`/api/v1/content/public/forum/topics/${topic.thread.id}`)
        .expect(404);
    }
    await request(context.app.getHttpServer())
      .get('/api/v1/content/public/forum/topics/not-a-uuid')
      .expect(400);
  });

  it('does not substitute a visible reply for a hidden topic root', async () => {
    const topic = await createTopic();
    const events = context.dataSource.getRepository(EventEntity);
    await events.update(topic.root.id, {
      metadata: { moderation: { hidden: true } },
    });
    await events.save(
      events.create({
        threadId: topic.thread.id,
        eventType: 'forum.reply.create',
        actorType: EventActorType.System,
        contentType: EventContentType.Text,
        content: 'Still readable reply',
        parentEventId: topic.root.id,
      }),
    );
    await expect(content.getPublicForumTopic(topic.thread.id)).rejects.toThrow(
      NotFoundException,
    );
    const listed = await content.listPublicForumTopics({ limit: '50' });
    expect(
      listed.topics.some((entry) => entry.threadId === topic.thread.id),
    ).toBe(false);
  });

  it('omits hidden and deleted replies from readable public topics', async () => {
    const topic = await createTopic();
    const events = context.dataSource.getRepository(EventEntity);
    for (const metadata of [
      {},
      { moderation: { hidden: true } },
      { moderation: { deleted: true } },
    ]) {
      await events.save(
        events.create({
          threadId: topic.thread.id,
          eventType: 'forum.reply.create',
          actorType: EventActorType.System,
          contentType: EventContentType.Text,
          content: 'Reply',
          parentEventId: topic.root.id,
          metadata,
        }),
      );
    }
    const result = await content.getPublicForumTopic(topic.thread.id);
    expect(result.topic.replies).toHaveLength(1);
  });

  it('does not expose private or hidden debates through list, detail, or archive', async () => {
    const host = await createUser();
    const debates = context.dataSource.getRepository(DebateSessionEntity);
    const threads = context.dataSource.getRepository(ThreadEntity);
    const ids: string[] = [];
    for (const state of [
      { visibility: ThreadVisibility.Private, metadata: {} },
      {
        visibility: ThreadVisibility.Public,
        metadata: { moderation: { hidden: true } },
      },
    ]) {
      const thread = await threads.save(
        threads.create({
          contextType: ThreadContextType.DebateSpectator,
          ...state,
        }),
      );
      const debate = await debates.save(
        debates.create({
          threadId: thread.id,
          topic: 'Private debate',
          proStance: 'Pro',
          conStance: 'Con',
          hostType: SubjectType.Human,
          hostUserId: host.id,
        }),
      );
      ids.push(debate.id);
      for (const suffix of ['', '/archive']) {
        await request(context.app.getHttpServer())
          .get(`/api/v1/debates/${debate.id}${suffix}`)
          .expect(404);
      }
    }
    const listed = await context.app.get(DebateService).listDebates();
    expect(
      listed.sessions.some((session) => ids.includes(session.debateSessionId)),
    ).toBe(false);
  });

  it('operator hide removes a debate publicly while preserving its operator archive', async () => {
    const host = await createUser();
    const threads = context.dataSource.getRepository(ThreadEntity);
    const thread = await threads.save(
      threads.create({
        contextType: ThreadContextType.DebateSpectator,
        visibility: ThreadVisibility.Public,
      }),
    );
    const debates = context.dataSource.getRepository(DebateSessionEntity);
    const debate = await debates.save(
      debates.create({
        threadId: thread.id,
        topic: 'Moderated debate',
        proStance: 'Pro',
        conStance: 'Con',
        hostType: SubjectType.Human,
        hostUserId: host.id,
      }),
    );
    const moderation = context.app.get(ModerationService);
    await moderation.applyOperatorAction({
      action: 'hide',
      targetType: 'debate_session',
      targetId: debate.id,
      reason: 'Test moderation',
    });
    await request(context.app.getHttpServer())
      .get(`/api/v1/debates/${debate.id}`)
      .expect(404);
    await request(context.app.getHttpServer())
      .get(`/api/v1/debates/${debate.id}/archive`)
      .expect(404);
    await expect(
      moderation.readDebateArchive(debate.id),
    ).resolves.toMatchObject({ debateSessionId: debate.id });
  });
  it('returns public profile fields without upload paths or arbitrary private metadata', async () => {
    const agent = await createAgent();
    await context.dataSource.getRepository(AgentEntity).update(agent.id, {
      profileMetadata: {
        headline: 'Public headline',
        pendingAvatarUpload: { key: 'private-path' },
        avatarStorageKey: 'private-path',
        internalToken: 'do-not-expose',
      },
    });
    const directory = await context.app
      .get(AgentsService)
      .readPublicDirectory();
    const entry = directory.agents.find(
      (candidate) => candidate.id === agent.id,
    );
    expect(entry?.profileMetadata).toEqual({ headline: 'Public headline' });
  });

  it('indexes every visible page with stable cursors and searches topics older than the latest 50', async () => {
    const needle = `old-topic-${randomUUID()}`;
    const oldTopic = await createTopic();
    await context.dataSource.getRepository(ForumTopicViewEntity).update(
      { threadId: oldTopic.thread.id },
      {
        title: needle,
        lastActivityAt: new Date('2000-01-01'),
      },
    );
    await Promise.all(Array.from({ length: 51 }, () => createTopic()));
    const privateTopic = await createTopic(ThreadVisibility.Private);
    const index = context.app.get(PublicIndexService);
    const ids: string[] = [];
    let cursor: string | undefined;
    do {
      const page = await index.readIndex('forum', cursor, '10');
      expect(page.items.length).toBeLessThanOrEqual(10);
      ids.push(...page.items.map((item) => item.id));
      cursor = page.nextCursor ?? undefined;
    } while (cursor);
    expect(ids).toEqual([...new Set(ids)].sort());
    expect(ids).toContain(oldTopic.thread.id);
    expect(ids).not.toContain(privateTopic.thread.id);
    expect(ids.length).toBeGreaterThan(50);
    const found = await content.listPublicForumTopics({
      query: needle,
      limit: '1',
    });
    expect(found.topics.map((topic) => topic.threadId)).toEqual([
      oldTopic.thread.id,
    ]);
    await request(context.app.getHttpServer())
      .get('/api/v1/public/index?type=forum&cursor=invalid')
      .expect(400);
    await request(context.app.getHttpServer())
      .get('/api/v1/public/index?type=invalid')
      .expect(400);

    const privateAgent = await createAgent();
    await context.dataSource
      .getRepository(AgentEntity)
      .update(privateAgent.id, { isPublic: false });
    const agents = await index.readIndex('agents', undefined, '100000');
    expect(agents.items.every((item) => item.handle && item.updatedAt)).toBe(
      true,
    );
    expect(agents.items.some((item) => item.id === privateAgent.id)).toBe(
      false,
    );
    const debates = await index.readIndex('debates');
    expect(debates.items).toEqual([]);
  });
  it('keeps the human as author when routing a first DM through an owned agent', async () => {
    const human = await createUser();
    const owned = await createAgent(human.id);
    const remote = await createAgent();
    const policy = context.app.get(PolicyService);
    await policy.upsertAgentSafetyPolicy(remote.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    const sent = await content.sendHumanDirectMessage(human, {
      activeAgentId: owned.id,
      recipientType: SubjectType.Agent,
      recipientAgentId: remote.id,
      content: 'Human-authored network message',
    });
    const event = await context.dataSource
      .getRepository(EventEntity)
      .findOneByOrFail({ id: sent.eventId });
    expect(event.actorType).toBe(EventActorType.Human);
    expect(event.actorUserId).toBe(human.id);
    expect(event.actorAgentId).toBeNull();
    const participants = await context.dataSource
      .getRepository(ThreadParticipantEntity)
      .findBy({ threadId: sent.threadId });
    expect(participants.some((entry) => entry.agentId === owned.id)).toBe(true);
    expect(participants.some((entry) => entry.agentId === remote.id)).toBe(
      true,
    );
  });
  it('authorizes attachment bytes by uploader or thread membership and prevents foreign reuse', async () => {
    const owner = await createUser();
    const outsider = await createUser();
    const recipient = await createUser();
    const agent = await createAgent(recipient.id);
    const strangerAgent = await createAgent();
    const assets = context.dataSource.getRepository(AssetEntity);
    const asset = await assets.save(
      assets.create({
        createdByUserId: owner.id,
        kind: AssetKind.Image,
        originalFileName: 'private.png',
        mimeType: 'image/png',
        storageBucket: 'test',
        storageKey: randomUUID(),
        uploadStatus: AssetUploadStatus.Uploaded,
        moderationStatus: AssetModerationStatus.Approved,
        byteSize: 13,
        uploadUrlExpiresAt: new Date(),
      }),
    );
    const assetService = context.app.get(AssetsService);
    await expect(
      assetService.readApprovedAssetForHuman(outsider, asset.id),
    ).rejects.toThrow(NotFoundException);
    await expect(
      assetService.readApprovedAssetForHuman(owner, asset.id),
    ).resolves.toMatchObject({ byteSize: 13 });
    await expect(
      content.createForumTopic(
        { type: SubjectType.Agent, id: strangerAgent.id },
        {
          title: 'Foreign attachment',
          contentType: 'image',
          assetId: asset.id,
        },
      ),
    ).rejects.toThrow(NotFoundException);

    const threads = context.dataSource.getRepository(ThreadEntity);
    const thread = await threads.save(
      threads.create({ contextType: ThreadContextType.DirectMessage }),
    );
    const events = context.dataSource.getRepository(EventEntity);
    await events.save(
      events.create({
        threadId: thread.id,
        actorType: EventActorType.Human,
        actorUserId: owner.id,
        eventType: 'dm.send',
        contentType: EventContentType.Image,
        assetId: asset.id,
      }),
    );
    const participants = context.dataSource.getRepository(
      ThreadParticipantEntity,
    );
    await participants.save(
      participants.create({
        threadId: thread.id,
        participantType: SubjectType.Agent,
        participantSubjectId: agent.id,
        agentId: agent.id,
      }),
    );
    await expect(
      assetService.readApprovedAssetForHuman(recipient, asset.id),
    ).resolves.toMatchObject({ byteSize: 13 });
    await expect(
      assetService.readApprovedAssetForHuman(outsider, asset.id),
    ).rejects.toThrow(NotFoundException);
    await expect(
      assetService.assertAssetReadable(asset, {
        type: SubjectType.Agent,
        id: agent.id,
      }),
    ).resolves.toBeUndefined();

    jest
      .spyOn(context.app.get(AuthService), 'authenticateHumanToken')
      .mockResolvedValue(outsider);
    await request(context.app.getHttpServer())
      .get(`/api/v1/assets/${asset.id}/content`)
      .set('Authorization', 'Bearer test')
      .expect(404);
  });
});
