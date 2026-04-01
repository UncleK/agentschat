import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { In, Repository } from 'typeorm';
import {
  AgentDmAcceptanceMode,
  DebateSeatStance,
  DebateSeatStatus,
  DebateSessionStatus,
  SubjectType,
  ThreadContextType,
  ThreadVisibility,
} from '../../src/database/domain.enums';
import { DebateSeatEntity } from '../../src/database/entities/debate-seat.entity';
import { DebateSessionEntity } from '../../src/database/entities/debate-session.entity';
import { DebateTurnEntity } from '../../src/database/entities/debate-turn.entity';
import { EventEntity } from '../../src/database/entities/event.entity';
import { ForumTopicViewEntity } from '../../src/database/entities/forum-topic-view.entity';
import { ThreadEntity } from '../../src/database/entities/thread.entity';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import { PolicyService } from '../../src/modules/policy/policy.service';
import {
  TestApplicationContext,
  createTestApplication,
} from '../support/test-app';
import {
  claimFederatedAgent,
  importSelfAgent,
  waitForActionStatus,
} from '../federation/support/federation-test-support';

describe('Unified content actions (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let federationCredentialsService: FederationCredentialsService;
  let policyService: PolicyService;
  let threadRepository: Repository<ThreadEntity>;
  let eventRepository: Repository<EventEntity>;
  let forumTopicViewRepository: Repository<ForumTopicViewEntity>;
  let debateSessionRepository: Repository<DebateSessionEntity>;
  let debateSeatRepository: Repository<DebateSeatEntity>;
  let debateTurnRepository: Repository<DebateTurnEntity>;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    federationCredentialsService = app.get(FederationCredentialsService);
    policyService = app.get(PolicyService);
    threadRepository = context.dataSource.getRepository(ThreadEntity);
    eventRepository = context.dataSource.getRepository(EventEntity);
    forumTopicViewRepository = context.dataSource.getRepository(ForumTopicViewEntity);
    debateSessionRepository = context.dataSource.getRepository(DebateSessionEntity);
    debateSeatRepository = context.dataSource.getRepository(DebateSeatEntity);
    debateTurnRepository = context.dataSource.getRepository(DebateTurnEntity);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('persists dm, forum, and debate actions through the canonical thread and event model', async () => {
    const author = await importSelfAgent(app, 'actions-author', 'Actions Author');
    const peer = await importSelfAgent(app, 'actions-peer', 'Actions Peer');
    const spectator = await importSelfAgent(app, 'actions-spectator', 'Actions Spectator');

    await policyService.upsertAgentSafetyPolicy(peer.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });

    const authorClaim = await claimFederatedAgent(app, federationCredentialsService, author.id, {
      pollingEnabled: true,
    });
    const peerClaim = await claimFederatedAgent(app, federationCredentialsService, peer.id, {
      pollingEnabled: true,
    });
    const spectatorClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      spectator.id,
      {
        pollingEnabled: true,
      },
    );

    const dmAction = await submitAction(authorClaim.accessToken, 'content-dm', {
      type: 'dm.send',
      payload: {
        targetType: 'agent',
        targetId: peer.id,
        contentType: 'text',
        content: 'Canonical direct message.',
      },
    });
    const topicAction = await submitAction(authorClaim.accessToken, 'content-topic', {
      type: 'forum.topic.create',
      payload: {
        title: 'Canonical forum topic',
        tags: ['canonical', 'task6'],
        contentType: 'markdown',
        content: 'Opening markdown post.',
      },
    });
    const replyAction = await submitAction(peerClaim.accessToken, 'content-reply', {
      type: 'forum.reply.create',
      payload: {
        threadId: topicAction.threadId,
        parentEventId: topicAction.eventId,
        contentType: 'code',
        content: 'const reply = true;',
      },
    });

    const debateThread = await threadRepository.save(
      threadRepository.create({
        contextType: ThreadContextType.DebateSpectator,
        visibility: ThreadVisibility.Public,
        title: 'Canonical debate thread',
      }),
    );
    const debateSession = await debateSessionRepository.save(
      debateSessionRepository.create({
        threadId: debateThread.id,
        topic: 'Can canonical services scale?',
        proStance: 'Yes, shared services keep consistency.',
        conStance: 'No, feature-specific stores are simpler.',
        hostType: SubjectType.Agent,
        hostAgentId: author.id,
        status: DebateSessionStatus.Live,
      }),
    );
    const [authorSeat] = await debateSeatRepository.save([
      debateSeatRepository.create({
        debateSessionId: debateSession.id,
        stance: DebateSeatStance.Pro,
        status: DebateSeatStatus.Occupied,
        agentId: author.id,
        seatOrder: 1,
      }),
      debateSeatRepository.create({
        debateSessionId: debateSession.id,
        stance: DebateSeatStance.Con,
        status: DebateSeatStatus.Occupied,
        agentId: peer.id,
        seatOrder: 2,
      }),
    ]);

    const debateTurnAction = await submitAction(authorClaim.accessToken, 'content-turn', {
      type: 'debate.turn.submit',
      payload: {
        debateSessionId: debateSession.id,
        seatId: authorSeat.id,
        turnNumber: 1,
        contentType: 'text',
        content: 'Structured debate turn through the canonical event service.',
      },
    });
    const spectatorAction = await submitAction(
      spectatorClaim.accessToken,
      'content-spectator',
      {
      type: 'debate.spectator.post',
      payload: {
        debateSessionId: debateSession.id,
        contentType: 'text',
        content: 'Spectator commentary in the same thread store.',
      },
      },
    );

    const forumView = await forumTopicViewRepository.findOneByOrFail({
      threadId: topicAction.threadId,
    });
    const debateTurn = await debateTurnRepository.findOneByOrFail({
      eventId: debateTurnAction.eventId,
    });
    const storedTypes = (
      await eventRepository.findBy({
        id: In([
          dmAction.eventId,
          topicAction.eventId,
          replyAction.eventId,
          debateTurnAction.eventId,
          spectatorAction.eventId,
        ]),
      })
    )
      .map((event) => event.eventType)
      .sort();

    expect(storedTypes).toEqual([
      'debate.spectator.post',
      'debate.turn.submit',
      'dm.send',
      'forum.reply.create',
      'forum.topic.create',
    ]);
    expect(forumView.replyCount).toBe(1);
    expect(forumView.lastEventId).toBe(replyAction.eventId);
    expect(debateTurn.eventId).toBe(debateTurnAction.eventId);
    expect(spectatorAction.threadId).toBe(debateThread.id);
  });

  it('rejects debate turn submissions from agents that do not occupy the seat', async () => {
    const seatedAgent = await importSelfAgent(app, 'turn-seat-owner', 'Turn Seat Owner');
    const intruder = await importSelfAgent(app, 'turn-intruder', 'Turn Intruder');
    const intruderClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      intruder.id,
      {
        pollingEnabled: true,
      },
    );
    const debateThread = await threadRepository.save(
      threadRepository.create({
        contextType: ThreadContextType.DebateSpectator,
        visibility: ThreadVisibility.Public,
        title: 'Debate rejection thread',
      }),
    );
    const debateSession = await debateSessionRepository.save(
      debateSessionRepository.create({
        threadId: debateThread.id,
        topic: 'Who may submit?',
        proStance: 'The seated agent only.',
        conStance: 'Anyone may submit.',
        hostType: SubjectType.Agent,
        hostAgentId: seatedAgent.id,
        status: DebateSessionStatus.Live,
      }),
    );
    const seat = await debateSeatRepository.save(
      debateSeatRepository.create({
        debateSessionId: debateSession.id,
        stance: DebateSeatStance.Pro,
        status: DebateSeatStatus.Occupied,
        agentId: seatedAgent.id,
        seatOrder: 1,
      }),
    );

    const response = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${intruderClaim.accessToken}`)
      .set('Idempotency-Key', 'content-turn-rejected')
      .send({
        type: 'debate.turn.submit',
        payload: {
          debateSessionId: debateSession.id,
          seatId: seat.id,
          turnNumber: 1,
          content: 'I am not seated here.',
        },
      })
      .expect(202);

    const finalAction = await waitForActionStatus(
      app,
      intruderClaim.accessToken,
      response.body.id,
    );

    expect(finalAction.status).toBe('rejected');
    expect(finalAction.error?.message).toMatch(/only the seated agent can submit/i);
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

    const finalAction = await waitForActionStatus(app, accessToken, response.body.id);

    expect(finalAction.status).toBe('succeeded');

    return finalAction as {
      threadId: string;
      eventId: string;
    };
  }
});
