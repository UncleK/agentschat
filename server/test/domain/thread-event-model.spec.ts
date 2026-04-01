import { randomUUID } from 'node:crypto';
import { DataSource, In } from 'typeorm';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { DebateSeatEntity } from '../../src/database/entities/debate-seat.entity';
import { DebateSessionEntity } from '../../src/database/entities/debate-session.entity';
import { DebateTurnEntity } from '../../src/database/entities/debate-turn.entity';
import { EventEntity } from '../../src/database/entities/event.entity';
import { ForumTopicViewEntity } from '../../src/database/entities/forum-topic-view.entity';
import { ThreadEntity } from '../../src/database/entities/thread.entity';
import { ThreadParticipantEntity } from '../../src/database/entities/thread-participant.entity';
import { UserEntity } from '../../src/database/entities/user.entity';
import {
  AgentOwnerType,
  AuthProvider,
  DebateSeatStance,
  DebateSeatStatus,
  DebateSessionStatus,
  DebateTurnStatus,
  EventActorType,
  EventContentType,
  SubjectType,
  ThreadContextType,
  ThreadParticipantRole,
  ThreadVisibility,
} from '../../src/database/domain.enums';
import {
  createDomainTestDataSource,
  destroyDomainTestDataSource,
} from './support/domain-test-database';

describe('Thread and Event canonical model', () => {
  let dataSource: DataSource;

  beforeAll(async () => {
    dataSource = await createDomainTestDataSource();
  });

  afterAll(async () => {
    await destroyDomainTestDataSource(dataSource);
  });

  it('reuses Thread and Event across DM, forum, and debate projections', async () => {
    const userRepository = dataSource.getRepository(UserEntity);
    const agentRepository = dataSource.getRepository(AgentEntity);
    const threadRepository = dataSource.getRepository(ThreadEntity);
    const threadParticipantRepository = dataSource.getRepository(
      ThreadParticipantEntity,
    );
    const eventRepository = dataSource.getRepository(EventEntity);
    const forumTopicViewRepository =
      dataSource.getRepository(ForumTopicViewEntity);
    const debateSessionRepository =
      dataSource.getRepository(DebateSessionEntity);
    const debateSeatRepository = dataSource.getRepository(DebateSeatEntity);
    const debateTurnRepository = dataSource.getRepository(DebateTurnEntity);

    const human = await userRepository.save(
      userRepository.create({
        email: `host-${randomUUID()}@example.com`,
        displayName: 'Debate Host',
        authProvider: AuthProvider.Email,
      }),
    );

    const agentA = await agentRepository.save(
      agentRepository.create({
        handle: 'alpha-agent',
        displayName: 'Alpha Agent',
        ownerType: AgentOwnerType.Self,
      }),
    );
    const agentB = await agentRepository.save(
      agentRepository.create({
        handle: 'beta-agent',
        displayName: 'Beta Agent',
        ownerType: AgentOwnerType.Self,
      }),
    );

    const dmThread = await threadRepository.save(
      threadRepository.create({
        contextType: ThreadContextType.DirectMessage,
        visibility: ThreadVisibility.Private,
      }),
    );
    await threadParticipantRepository.save([
      threadParticipantRepository.create({
        threadId: dmThread.id,
        participantType: SubjectType.Agent,
        participantSubjectId: agentA.id,
        agentId: agentA.id,
        role: ThreadParticipantRole.Member,
      }),
      threadParticipantRepository.create({
        threadId: dmThread.id,
        participantType: SubjectType.Human,
        participantSubjectId: human.id,
        userId: human.id,
        role: ThreadParticipantRole.Member,
      }),
    ]);
    const dmEvent = await eventRepository.save(
      eventRepository.create({
        threadId: dmThread.id,
        eventType: 'dm.send',
        actorType: EventActorType.Agent,
        actorAgentId: agentA.id,
        contentType: EventContentType.Text,
        content: 'Private hello from the canonical event model.',
      }),
    );

    const forumThread = await threadRepository.save(
      threadRepository.create({
        contextType: ThreadContextType.ForumTopic,
        visibility: ThreadVisibility.Public,
        title: 'Is aligned AI debate-friendly?',
      }),
    );
    const forumRootEvent = await eventRepository.save(
      eventRepository.create({
        threadId: forumThread.id,
        eventType: 'forum.topic.create',
        actorType: EventActorType.Agent,
        actorAgentId: agentA.id,
        contentType: EventContentType.Markdown,
        content: 'Opening thesis for the forum topic.',
        metadata: {
          title: 'Is aligned AI debate-friendly?',
          tags: ['alignment'],
        },
      }),
    );
    const forumReplyEvent = await eventRepository.save(
      eventRepository.create({
        threadId: forumThread.id,
        eventType: 'forum.reply.create',
        actorType: EventActorType.Agent,
        actorAgentId: agentB.id,
        parentEventId: forumRootEvent.id,
        contentType: EventContentType.Text,
        content: 'Replying inside the same thread and event store.',
      }),
    );
    const forumTopicView = await forumTopicViewRepository.save(
      forumTopicViewRepository.create({
        threadId: forumThread.id,
        rootEventId: forumRootEvent.id,
        title: 'Is aligned AI debate-friendly?',
        tags: ['alignment'],
        replyCount: 1,
        followCount: 0,
        lastEventId: forumReplyEvent.id,
      }),
    );

    const debateThread = await threadRepository.save(
      threadRepository.create({
        contextType: ThreadContextType.DebateSpectator,
        visibility: ThreadVisibility.Public,
        title: 'Debate on alignment controls',
      }),
    );
    const debateSession = await debateSessionRepository.save(
      debateSessionRepository.create({
        threadId: debateThread.id,
        topic: 'Debate on alignment controls',
        proStance: 'Strict safeguards improve outcomes.',
        conStance: 'Strict safeguards restrict capability.',
        hostType: SubjectType.Human,
        hostUserId: human.id,
        status: DebateSessionStatus.Live,
      }),
    );
    const [proSeat, conSeat] = await debateSeatRepository.save([
      debateSeatRepository.create({
        debateSessionId: debateSession.id,
        stance: DebateSeatStance.Pro,
        status: DebateSeatStatus.Occupied,
        agentId: agentA.id,
        seatOrder: 1,
      }),
      debateSeatRepository.create({
        debateSessionId: debateSession.id,
        stance: DebateSeatStance.Con,
        status: DebateSeatStatus.Occupied,
        agentId: agentB.id,
        seatOrder: 2,
      }),
    ]);
    const debateTurnEvent = await eventRepository.save(
      eventRepository.create({
        threadId: debateThread.id,
        eventType: 'debate.turn.submit',
        actorType: EventActorType.Agent,
        actorAgentId: agentA.id,
        targetType: 'debate_session',
        targetId: debateSession.id,
        contentType: EventContentType.Text,
        content: 'Formal debate turn stored in the canonical events table.',
      }),
    );
    const spectatorEvent = await eventRepository.save(
      eventRepository.create({
        threadId: debateThread.id,
        eventType: 'debate.spectator.post',
        actorType: EventActorType.Human,
        actorUserId: human.id,
        targetType: 'debate_session',
        targetId: debateSession.id,
        contentType: EventContentType.Text,
        content: 'Spectator feed also reuses the same thread/event model.',
      }),
    );
    const debateTurn = await debateTurnRepository.save(
      debateTurnRepository.create({
        debateSessionId: debateSession.id,
        seatId: proSeat.id,
        turnNumber: 1,
        status: DebateTurnStatus.Completed,
        eventId: debateTurnEvent.id,
      }),
    );
    const storedDebateTurn = await debateTurnRepository.findOneByOrFail({
      id: debateTurn.id,
    });

    const events = await eventRepository.findBy({
      threadId: In([dmThread.id, forumThread.id, debateThread.id]),
    });

    expect(events).toHaveLength(5);
    expect(events.map((event) => event.eventType).sort()).toEqual([
      'debate.spectator.post',
      'debate.turn.submit',
      'dm.send',
      'forum.reply.create',
      'forum.topic.create',
    ]);
    expect(forumTopicView.threadId).toBe(forumThread.id);
    expect(forumTopicView.rootEventId).toBe(forumRootEvent.id);
    expect(storedDebateTurn.eventId).toBe(debateTurnEvent.id);
    expect(spectatorEvent.threadId).toBe(debateThread.id);
    expect(conSeat.debateSessionId).toBe(debateSession.id);

    const forbiddenTables = await dataSource.query(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name IN ('messages', 'forum_replies', 'forum_topics', 'debate_messages')
    `);

    expect(forbiddenTables).toEqual([]);
    expect(dmEvent.threadId).toBe(dmThread.id);
  });
});
