import { randomUUID } from 'node:crypto';
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import request from 'supertest';
import {
  AgentOwnerType,
  AgentStatus,
  AssetKind,
  AssetModerationStatus,
  AssetUploadStatus,
  AuthProvider,
  DebateSessionStatus,
  DebateSeatStatus,
  DebateTurnStatus,
  EventActorType,
  EventContentType,
  SubjectType,
  ThreadContextType,
  ThreadParticipantRole,
  ThreadVisibility,
} from '../../src/database/domain.enums';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { AssetEntity } from '../../src/database/entities/asset.entity';
import { DebateSessionEntity } from '../../src/database/entities/debate-session.entity';
import { DebateTurnEntity } from '../../src/database/entities/debate-turn.entity';
import { EventEntity } from '../../src/database/entities/event.entity';
import { ForumTopicViewEntity } from '../../src/database/entities/forum-topic-view.entity';
import { ThreadEntity } from '../../src/database/entities/thread.entity';
import { ThreadParticipantEntity } from '../../src/database/entities/thread-participant.entity';
import { UserEntity } from '../../src/database/entities/user.entity';
import { AuthenticatedHuman } from '../../src/modules/auth/auth.types';
import { AssetsService } from '../../src/modules/assets/assets.service';
import { AssetStorageService } from '../../src/modules/assets/asset-storage.service';
import { ContentService } from '../../src/modules/content/content.service';
import { DebateService } from '../../src/modules/debate/debate.service';
import { PolicyService } from '../../src/modules/policy/policy.service';
import {
  createTestApplication,
  TestApplicationContext,
} from '../support/test-app';

describe('Conversation identity, lifecycle concurrency and public discovery', () => {
  let context: TestApplicationContext;
  let content: ContentService;
  let debates: DebateService;

  beforeAll(async () => {
    context = await createTestApplication();
    content = context.app.get(ContentService);
    debates = context.app.get(DebateService);
    jest
      .spyOn(context.app.get(PolicyService), 'assertDirectMessageAllowed')
      .mockResolvedValue(undefined);
  });
  afterAll(async () => {
    await context?.close();
  });

  async function human(): Promise<AuthenticatedHuman> {
    const repository = context.dataSource.getRepository(UserEntity);
    const id = randomUUID();
    const user = await repository.save(
      repository.create({
        email: `${id}@example.com`,
        username: id.replaceAll('-', '').slice(0, 20),
        displayName: `Human ${id}`,
        authProvider: AuthProvider.Email,
      }),
    );
    return { ...user, emailVerified: true };
  }
  async function agent(ownerUserId?: string) {
    const repository = context.dataSource.getRepository(AgentEntity);
    return repository.save(
      repository.create({
        handle: `discovery-${randomUUID()}`,
        displayName: 'Conversation agent',
        ownerType: ownerUserId ? AgentOwnerType.Human : AgentOwnerType.Self,
        ownerUserId: ownerUserId ?? null,
        status: AgentStatus.Online,
      }),
    );
  }
  async function openNetwork(local: AgentEntity, remote: AgentEntity) {
    return content.sendAgentDirectMessage(local.id, {
      recipient: { type: SubjectType.Agent, id: remote.id },
      content: 'Original agent message',
    });
  }

  it('paginates all 51 public forum roots with precise timestamp ties and preserves original publication dates', async () => {
    const threads = context.dataSource.getRepository(ThreadEntity);
    const events = context.dataSource.getRepository(EventEntity);
    const topics = context.dataSource.getRepository(ForumTopicViewEntity);
    const ids: string[] = [];
    const published = new Date('2026-01-01T01:02:03.456Z');
    for (let index = 0; index < 52; index++) {
      const thread = await threads.save(
        threads.create({
          contextType: ThreadContextType.ForumTopic,
          visibility:
            index === 51 ? ThreadVisibility.Private : ThreadVisibility.Public,
        }),
      );
      const root = await events.save(
        events.create({
          threadId: thread.id,
          eventType: 'forum.topic.create',
          actorType: EventActorType.System,
          contentType: EventContentType.Text,
          content: 'pagination root',
          occurredAt: published,
        }),
      );
      await topics.save(
        topics.create({
          threadId: thread.id,
          rootEventId: root.id,
          title: 'pagination root',
          lastActivityAt: new Date(),
        }),
      );
      if (index < 51) ids.push(thread.id);
    }
    await context.dataSource.query(
      `UPDATE forum_topic_views SET last_activity_at = '2026-09-12T12:00:00.123456Z'`,
    );
    const first = await content.listPublicForumTopics({
      query: 'pagination',
      limit: '50',
    });
    expect(first.topics).toHaveLength(50);
    expect(first.nextCursor).toEqual(expect.any(String));
    expect(
      first.topics.every(
        (topic) => topic.createdAt === published.toISOString(),
      ),
    ).toBe(true);
    const second = await content.listPublicForumTopics({
      query: 'pagination',
      limit: '50',
      cursor: first.nextCursor,
    });
    expect(second.topics).toHaveLength(1);
    expect(second.nextCursor).toBeNull();
    expect(
      [...first.topics, ...second.topics].map((topic) => topic.threadId),
    ).toEqual(ids.sort().reverse());
    await expect(
      content.listPublicForumTopics({
        query: 'other',
        cursor: first.nextCursor,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    const detail = await content.getPublicForumTopic(ids[0]);
    expect(detail.topic.createdAt).toBe(published.toISOString());
    await request(context.app.getHttpServer())
      .get('/api/v1/content/public/forum/topics')
      .query({ cursor: 'broken' })
      .expect(400);
  });

  it('paginates finished debates including ended and archived sessions, without sweeping a live list', async () => {
    const host = await human();
    const threads = context.dataSource.getRepository(ThreadEntity);
    const sessions = context.dataSource.getRepository(DebateSessionEntity);
    const ids: string[] = [];
    for (let index = 0; index < 27; index++) {
      const thread = await threads.save(
        threads.create({
          contextType: ThreadContextType.DebateSpectator,
          visibility:
            index === 26 ? ThreadVisibility.Private : ThreadVisibility.Public,
        }),
      );
      const session = await sessions.save(
        sessions.create({
          threadId: thread.id,
          topic: 'archive pagination',
          proStance: 'pro',
          conStance: 'con',
          hostType: SubjectType.Human,
          hostUserId: host.id,
          status:
            index % 2
              ? DebateSessionStatus.Archived
              : DebateSessionStatus.Ended,
        }),
      );
      if (index < 26) ids.push(session.id);
    }
    await context.dataSource.query(
      `UPDATE debate_sessions SET created_at = '2026-09-12T12:00:00.123456Z'`,
    );
    const first = await debates.listDebates(24, null, 'finished');
    const second = await debates.listDebates(24, first.nextCursor, 'finished');
    expect(first.sessions).toHaveLength(24);
    expect(second.sessions).toHaveLength(2);
    expect(second.nextCursor).toBeNull();
    expect(
      [...first.sessions, ...second.sessions].map(
        (session) => session.debateSessionId,
      ),
    ).toEqual(ids.sort().reverse());
    await expect(
      debates.listDebates(24, first.nextCursor, 'archived'),
    ).rejects.toBeInstanceOf(BadRequestException);
    await request(context.app.getHttpServer())
      .get('/api/v1/debates')
      .query({ status: 'not-a-status' })
      .expect(400);
    const oldLive = ids[0];
    await sessions.update(oldLive, {
      status: DebateSessionStatus.Live,
      startedAt: new Date('2020-01-01'),
    });
    expect(
      (await debates.listDebates(24, null, 'live')).sessions.map(
        (session) => session.debateSessionId,
      ),
    ).toContain(oldLive);
    expect((await sessions.findOneByOrFail({ id: oldLive })).status).toBe(
      DebateSessionStatus.Live,
    );
  });

  it('exposes current owners in four-party DM, revokes former owners, and never relabels historical human authors', async () => {
    const oldOwner = await human();
    const remoteOwner = await human();
    const newOwner = await human();
    const local = await agent(oldOwner.id);
    const remote = await agent(remoteOwner.id);
    const opened = await openNetwork(local, remote);
    const authored = await content.sendHumanDirectMessageToThread(
      oldOwner,
      opened.threadId,
      { activeAgentId: local.id, content: 'Human-authored original' },
    );
    const event = await context.dataSource
      .getRepository(EventEntity)
      .findOneByOrFail({ id: authored.message.eventId });
    expect(event.actorType).toBe(EventActorType.Human);
    expect(event.actorUserId).toBe(oldOwner.id);
    expect(event.targetId).toBe(remote.id);
    const before = await content.getDirectMessageThreadMessages(
      oldOwner,
      opened.threadId,
      { activeAgentId: local.id },
    );
    expect(before.participants).toHaveLength(4);
    expect(
      before.participants.find((participant) => participant.id === local.id)
        ?.ownerUserId,
    ).toBe(oldOwner.id);
    await context.dataSource
      .getRepository(AgentEntity)
      .update(local.id, { ownerUserId: newOwner.id });
    await expect(
      content.getDirectMessageThreadMessages(oldOwner, opened.threadId, {
        activeAgentId: local.id,
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    await expect(
      content.sendHumanDirectMessageToThread(oldOwner, opened.threadId, {
        activeAgentId: local.id,
        content: 'stale owner',
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    const after = await content.getDirectMessageThreadMessages(
      newOwner,
      opened.threadId,
      { activeAgentId: local.id },
    );
    expect(after.participants.map((participant) => participant.id)).toEqual(
      expect.arrayContaining([
        local.id,
        remote.id,
        newOwner.id,
        remoteOwner.id,
      ]),
    );
    expect(
      after.participants.some((participant) => participant.id === oldOwner.id),
    ).toBe(false);
    expect(
      after.messages.find(
        (message) => message.eventId === authored.message.eventId,
      )?.actor.id,
    ).toBe(oldOwner.id);
    await expect(
      content.sendAgentDirectMessage(remote.id, {
        threadId: opened.threadId,
        recipient: { type: SubjectType.Human, id: oldOwner.id },
        content: 'stale recipient',
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
    // Historical participant remains stored; it is not an access grant.
    expect(
      await context.dataSource.getRepository(ThreadParticipantEntity).countBy({
        threadId: opened.threadId,
        participantSubjectId: oldOwner.id,
        role: ThreadParticipantRole.Spectator,
      }),
    ).toBe(1);
  });

  it('deduplicates shared owners, represents self-owned agents honestly, and isolates active-agent scopes', async () => {
    const owner = await human();
    const local = await agent(owner.id);
    const remote = await agent(owner.id);
    const unrelated = await agent(owner.id);
    const opened = await openNetwork(local, remote);
    expect(
      (
        await content.getDirectMessageThreadMessages(owner, opened.threadId, {
          activeAgentId: local.id,
        })
      ).participants,
    ).toHaveLength(3);
    await context.dataSource
      .getRepository(AgentEntity)
      .update(remote.id, { ownerType: AgentOwnerType.Self, ownerUserId: null });
    const page = await content.getDirectMessageThreadMessages(
      owner,
      opened.threadId,
      { activeAgentId: local.id },
    );
    expect(page.participants).toHaveLength(3);
    expect(
      page.participants.find((participant) => participant.id === remote.id)
        ?.ownerUserId,
    ).toBeNull();
    expect(
      page.participants
        .filter((participant) => participant.type === SubjectType.Human)
        .every((participant) => !participant.isOnline),
    ).toBe(true);
    await expect(
      content.getDirectMessageThreadMessages(owner, opened.threadId, {
        activeAgentId: unrelated.id,
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
    await expect(
      content.sendAgentDirectMessage(unrelated.id, {
        activeAgentId: local.id,
        threadId: opened.threadId,
        recipient: { type: SubjectType.Agent, id: remote.id },
        content: 'forged agent context',
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
    await expect(
      content.sendHumanDirectMessage(owner, {
        actorType: 'agent',
        actorAgentId: local.id,
        activeAgentId: local.id,
        recipientType: SubjectType.Agent,
        recipientAgentId: remote.id,
        content: 'forged authorship',
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('revokes a former DM owner from peer attachments while keeping current-owner and original-uploader access', async () => {
    const oldOwner = await human();
    const newOwner = await human();
    const peerOwner = await human();
    const outsider = await human();
    const local = await agent(oldOwner.id);
    const peer = await agent(peerOwner.id);
    const opened = await openNetwork(local, peer);
    const assets = context.dataSource.getRepository(AssetEntity);
    const uploaded = [] as AssetEntity[];
    for (const uploader of [peerOwner, oldOwner]) {
      const asset = await assets.save(
        assets.create({
          createdByUserId: uploader.id,
          kind: AssetKind.Image,
          originalFileName: 'dm-owner-transfer.png',
          mimeType: 'image/png',
          storageBucket: 'fixture',
          storageKey: randomUUID(),
          byteSize: 13,
          uploadStatus: AssetUploadStatus.Uploaded,
          moderationStatus: AssetModerationStatus.Approved,
          uploadUrlExpiresAt: new Date(),
        }),
      );
      await context.dataSource.getRepository(EventEntity).save({
        threadId: opened.threadId,
        eventType: 'dm.send',
        actorType: EventActorType.Human,
        actorUserId: uploader.id,
        contentType: EventContentType.Image,
        assetId: asset.id,
      });
      uploaded.push(asset);
    }
    const reader = context.app.get(AssetsService);
    const storage = jest
      .spyOn(context.app.get(AssetStorageService), 'readObject')
      .mockResolvedValue({
        body: Buffer.from('fixture image'),
        byteSize: 13,
        mimeType: 'image/png',
      });
    try {
      await expect(
        reader.readApprovedAssetForHuman(oldOwner, uploaded[0].id),
      ).resolves.toMatchObject({ byteSize: 13 });
      await context.dataSource
        .getRepository(AgentEntity)
        .update(local.id, { ownerUserId: newOwner.id });
      await expect(
        reader.readApprovedAssetForHuman(oldOwner, uploaded[0].id),
      ).rejects.toBeInstanceOf(NotFoundException);
      await expect(
        reader.readApprovedAssetForHuman(newOwner, uploaded[0].id),
      ).resolves.toMatchObject({ byteSize: 13 });
      await expect(
        reader.readApprovedAssetForHuman(newOwner, uploaded[1].id),
      ).resolves.toMatchObject({ byteSize: 13 });
      await expect(
        reader.readApprovedAssetForHuman(oldOwner, uploaded[1].id),
      ).resolves.toMatchObject({ byteSize: 13 });
      await expect(
        reader.readApprovedAssetForHuman(peerOwner, uploaded[1].id),
      ).resolves.toMatchObject({ byteSize: 13 });
      await expect(
        reader.readApprovedAssetForHuman(outsider, uploaded[0].id),
      ).rejects.toBeInstanceOf(NotFoundException);
    } finally {
      storage.mockRestore();
    }
  });

  it('serializes opposite-direction first sends into one private network thread', async () => {
    const local = await agent();
    const remote = await agent();
    const result = await Promise.all([
      openNetwork(local, remote),
      openNetwork(remote, local),
      openNetwork(local, remote),
    ]);
    expect(new Set(result.map((message) => message.threadId)).size).toBe(1);
    const rows: Array<{ count: string }> = await context.dataSource.query(
      `SELECT COUNT(DISTINCT thread_id) AS count FROM thread_participants WHERE participant_type = 'agent' AND participant_subject_id = $1`,
      [local.id],
    );
    expect(Number(rows[0].count)).toBe(1);
    const stored = await context.dataSource
      .getRepository(EventEntity)
      .findBy({ threadId: result[0].threadId });
    expect(stored).toHaveLength(3);
    expect(stored.every((event) => event.actorAgentId !== event.targetId)).toBe(
      true,
    );
  });

  async function liveFixture() {
    const host = await human();
    const pro = await agent();
    const con = await agent();
    const session = await debates.createHumanHostedDebate(host, {
      topic: 'Concurrent lifecycle',
      proStance: 'pro',
      conStance: 'con',
      proAgentId: pro.id,
      conAgentId: con.id,
      freeEntry: true,
    });
    return {
      host: { type: SubjectType.Human, id: host.id },
      pro,
      con,
      session,
    };
  }

  function expectOneTransition(results: PromiseSettledResult<unknown>[]) {
    expect(
      results.filter((result) => result.status === 'fulfilled'),
    ).toHaveLength(1);
    for (const result of results)
      if (result.status === 'rejected')
        expect(result.reason).toBeInstanceOf(ConflictException);
  }

  it('reserves a debater in only one active session even when hosts create sessions concurrently', async () => {
    const host = await human();
    const pro = await agent();
    const con = await agent();
    const create = () =>
      debates.createHumanHostedDebate(host, {
        topic: 'Concurrent reservation',
        proStance: 'pro',
        conStance: 'con',
        proAgentId: pro.id,
        conAgentId: con.id,
      });
    expectOneTransition(
      await Promise.allSettled([create(), create(), create()]),
    );
  });

  it('rechecks spectator writes inside the lifecycle lock when the host ends after the initial permission check', async () => {
    const { host, session } = await liveFixture();
    await debates.startDebate(host, session.debateSessionId);
    let checked!: () => void;
    let release!: () => void;
    const entered = new Promise<void>((resolve) => {
      checked = resolve;
    });
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    const original = debates.assertSpectatorCommentAllowed.bind(debates);
    const spy = jest
      .spyOn(debates, 'assertSpectatorCommentAllowed')
      .mockImplementation(async (actor, id, manager) => {
        const result = await original(actor, id, manager);
        if (!manager && id === session.debateSessionId) {
          checked();
          await gate;
        }
        return result;
      });
    try {
      const pending = content.postDebateSpectatorComment(host, {
        debateSessionId: session.debateSessionId,
        content: 'Must not enter a finished transcript',
      });
      const rejected =
        expect(pending).rejects.toBeInstanceOf(ForbiddenException);
      await entered;
      await debates.endDebate(host, session.debateSessionId);
      release();
      await rejected;
      expect(
        await context.dataSource.getRepository(EventEntity).countBy({
          threadId: session.threadId,
          eventType: 'debate.spectator.post',
        }),
      ).toBe(0);
    } finally {
      release();
      spy.mockRestore();
    }
  });

  it('serializes simultaneous start, turn submission and end without duplicate lifecycle events', async () => {
    const { host, pro, session } = await liveFixture();
    expectOneTransition(
      await Promise.allSettled(
        Array.from({ length: 4 }, () =>
          debates.startDebate(host, session.debateSessionId),
        ),
      ),
    );
    expectOneTransition(
      await Promise.allSettled(
        Array.from({ length: 4 }, () =>
          content.submitDebateTurn(pro.id, {
            debateSessionId: session.debateSessionId,
            turnNumber: 1,
            content: 'One formal turn',
          }),
        ),
      ),
    );
    expectOneTransition(
      await Promise.allSettled(
        Array.from({ length: 4 }, () =>
          debates.endDebate(host, session.debateSessionId),
        ),
      ),
    );
    const events = context.dataSource.getRepository(EventEntity);
    for (const eventType of [
      'debate.started',
      'debate.turn.submit',
      'debate.ended',
    ]) {
      expect(
        await events.countBy({ threadId: session.threadId, eventType }),
      ).toBe(1);
    }
    const view = await debates.getDebate(session.debateSessionId);
    expect(view.status).toBe(DebateSessionStatus.Ended);
    expect(view.formalTurns[0].event?.content).toBe('One formal turn');
    expect(view.formalTurns[1].status).toBe(DebateTurnStatus.Skipped);
    expect(view.currentTurn).toBeNull();
  });

  it('sweeps an expired turn once under concurrent reads and retains a single replacement transition', async () => {
    const { host, session } = await liveFixture();
    await debates.startDebate(host, session.debateSessionId);
    await context.dataSource
      .getRepository(DebateTurnEntity)
      .update(
        { debateSessionId: session.debateSessionId, turnNumber: 1 },
        { deadlineAt: new Date(Date.now() - 1000) },
      );
    await Promise.all(
      Array.from({ length: 5 }, () =>
        debates.sweepDebateSession(session.debateSessionId),
      ),
    );
    for (const eventType of [
      'debate.turn.missed',
      'debate.paused',
      'debate.seat.replacement_needed',
    ]) {
      expect(
        await context.dataSource
          .getRepository(EventEntity)
          .countBy({ threadId: session.threadId, eventType }),
      ).toBe(1);
    }
    const view = await debates.getDebate(session.debateSessionId);
    expect(view.status).toBe(DebateSessionStatus.Paused);
    expect(view.currentTurnNumber).toBe(2);
    expect(
      view.seats.filter((seat) => seat.status === DebateSeatStatus.Replacing),
    ).toHaveLength(1);
    await expect(
      debates.resumeDebate(host, session.debateSessionId),
    ).rejects.toBeInstanceOf(ConflictException);
    const replacement = await agent();
    await debates.assignReplacementSeat(host, {
      debateSessionId: session.debateSessionId,
      agentId: replacement.id,
    });
    await debates.resumeDebate(host, session.debateSessionId);
    await content.submitDebateTurn(replacement.id, {
      debateSessionId: session.debateSessionId,
      turnNumber: 2,
      content: 'Replacement original',
    });
    expect(
      (await debates.getDebate(session.debateSessionId)).formalTurns[1].event
        ?.actorAgentId,
    ).toBe(replacement.id);
  });
});
