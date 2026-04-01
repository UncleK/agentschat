import { randomUUID } from 'node:crypto';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { Repository } from 'typeorm';
import {
  DebateSeatEntity,
} from '../../src/database/entities/debate-seat.entity';
import { DebateSessionEntity } from '../../src/database/entities/debate-session.entity';
import { DebateTurnEntity } from '../../src/database/entities/debate-turn.entity';
import { EventEntity } from '../../src/database/entities/event.entity';
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

describe('Debate state machine (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let federationCredentialsService: FederationCredentialsService;
  let debateSessionRepository: Repository<DebateSessionEntity>;
  let debateSeatRepository: Repository<DebateSeatEntity>;
  let debateTurnRepository: Repository<DebateTurnEntity>;
  let eventRepository: Repository<EventEntity>;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    federationCredentialsService = app.get(FederationCredentialsService);
    debateSessionRepository = context.dataSource.getRepository(DebateSessionEntity);
    debateSeatRepository = context.dataSource.getRepository(DebateSeatEntity);
    debateTurnRepository = context.dataSource.getRepository(DebateTurnEntity);
    eventRepository = context.dataSource.getRepository(EventEntity);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('rejects malformed debate ids with 4xx while preserving 404 for valid missing ids', async () => {
    const missingDebateId = randomUUID();

    await request(app.getHttpServer())
      .get('/api/v1/debates/not-a-real-debate')
      .expect(400);

    await request(app.getHttpServer())
      .get('/api/v1/debates/not-a-real-debate/archive')
      .expect(400);

    await request(app.getHttpServer())
      .get(`/api/v1/debates/${missingDebateId}`)
      .expect(404)
      .expect(({ body }) => {
        expect(body.message).toMatch(/debate session/i);
      });

    await request(app.getHttpServer())
      .get(`/api/v1/debates/${missingDebateId}/archive`)
      .expect(404)
      .expect(({ body }) => {
        expect(body.message).toMatch(/debate session/i);
      });
  });

  it('enforces strict turns, separates spectators, pauses on a missed turn, and archives replay after end', async () => {
    const host = await registerHuman(app, 'debate-host@example.com', 'Debate Host');
    const pro = await importSelfAgent(app, 'debate-pro', 'Debate Pro');
    const con = await importSelfAgent(app, 'debate-con', 'Debate Con');
    const replacement = await importSelfAgent(app, 'debate-replacement', 'Debate Replacement');
    const spectator = await importSelfAgent(app, 'debate-spectator', 'Debate Spectator');
    const proClaim = await claimFederatedAgent(app, federationCredentialsService, pro.id, {
      pollingEnabled: true,
    });
    const conClaim = await claimFederatedAgent(app, federationCredentialsService, con.id, {
      pollingEnabled: true,
    });
    const replacementClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      replacement.id,
      {
        pollingEnabled: true,
      },
    );
    const spectatorClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      spectator.id,
      {
        pollingEnabled: true,
      },
    );

    const createResponse = await request(app.getHttpServer())
      .post('/api/v1/debates')
      .set('Authorization', `Bearer ${host.accessToken}`)
      .send({
        topic: 'Should debate state live on the server?',
        proStance: 'Yes, the server must own the lifecycle.',
        conStance: 'No, clients can infer enough state locally.',
        proAgentId: pro.id,
        conAgentId: con.id,
        freeEntry: true,
      })
      .expect(201);

    const debateSessionId = createResponse.body.debateSessionId as string;
    const createdSeats = await debateSeatRepository.find({
      where: { debateSessionId },
      order: { seatOrder: 'ASC' },
    });

    expect(createResponse.body.status).toBe('pending');
    expect(createdSeats).toHaveLength(2);
    expect(createdSeats[0].stance).toBe('pro');
    expect(createdSeats[1].stance).toBe('con');

    await request(app.getHttpServer())
      .post(`/api/v1/debates/${debateSessionId}/start`)
      .set('Authorization', `Bearer ${host.accessToken}`)
      .expect(201)
      .expect(({ body }) => {
        expect(body.status).toBe('live');
        expect(body.currentTurnNumber).toBe(1);
      });

    const openingView = await request(app.getHttpServer())
      .get(`/api/v1/debates/${debateSessionId}`)
      .expect(200);

    expect(openingView.body.currentTurn.turnNumber).toBe(1);
    expect(openingView.body.currentTurn.seatId).toBe(createdSeats[0].id);
    expect(openingView.body.formalTurns).toHaveLength(1);
    expect(openingView.body.spectatorFeed).toHaveLength(0);

    const outOfTurnAction = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${conClaim.accessToken}`)
      .set('Idempotency-Key', 'debate-out-of-turn')
      .send({
        type: 'debate.turn.submit',
        payload: {
          debateSessionId,
          turnNumber: 1,
          content: 'Trying to speak out of turn.',
        },
      })
      .expect(202);

    const outOfTurnResult = await waitForActionStatus(
      app,
      conClaim.accessToken,
      outOfTurnAction.body.id,
    );

    expect(outOfTurnResult.status).toBe('rejected');
    expect(outOfTurnResult.error?.message).toMatch(/not this seat's turn/i);

    const debaterSpectatorAction = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${proClaim.accessToken}`)
      .set('Idempotency-Key', 'debate-debater-spectator')
      .send({
        type: 'debate.spectator.post',
        payload: {
          debateSessionId,
          content: 'I should not be allowed into the spectator feed.',
        },
      })
      .expect(202);

    const debaterSpectatorResult = await waitForActionStatus(
      app,
      proClaim.accessToken,
      debaterSpectatorAction.body.id,
    );

    expect(debaterSpectatorResult.status).toBe('rejected');
    expect(debaterSpectatorResult.error?.message).toMatch(/spectator feed/i);

    const spectatorAction = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${spectatorClaim.accessToken}`)
      .set('Idempotency-Key', 'debate-spectator-post')
      .send({
        type: 'debate.spectator.post',
        payload: {
          debateSessionId,
          content: 'Spectators stay separate from formal turns.',
        },
      })
      .expect(202);

    const spectatorResult = await waitForActionStatus(
      app,
      spectatorClaim.accessToken,
      spectatorAction.body.id,
    );

    expect(spectatorResult.status).toBe('succeeded');

    const openingTurnAction = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${proClaim.accessToken}`)
      .set('Idempotency-Key', 'debate-opening-turn')
      .send({
        type: 'debate.turn.submit',
        payload: {
          debateSessionId,
          seatId: createdSeats[0].id,
          turnNumber: 1,
          content: 'Server-owned debate state is the only safe source of truth.',
        },
      })
      .expect(202);

    const openingTurnResult = await waitForActionStatus(
      app,
      proClaim.accessToken,
      openingTurnAction.body.id,
    );

    expect(openingTurnResult.status).toBe('succeeded');

    const afterOpeningTurn = await request(app.getHttpServer())
      .get(`/api/v1/debates/${debateSessionId}`)
      .expect(200);

    expect(afterOpeningTurn.body.currentTurn.turnNumber).toBe(2);
    expect(afterOpeningTurn.body.currentTurn.seatId).toBe(createdSeats[1].id);
    expect(afterOpeningTurn.body.spectatorFeed).toHaveLength(1);
    expect(afterOpeningTurn.body.spectatorFeed[0].content).toBe(
      'Spectators stay separate from formal turns.',
    );
    expect(
      afterOpeningTurn.body.formalTurns.find(
        (turn: { turnNumber: number }) => turn.turnNumber === 1,
      ).event.content,
    ).toBe('Server-owned debate state is the only safe source of truth.');

    const pendingConTurn = await debateTurnRepository.findOneByOrFail({
      debateSessionId,
      turnNumber: 2,
    });

    await debateTurnRepository.update(
      { id: pendingConTurn.id },
      {
        deadlineAt: new Date(Date.now() - 1_000),
      },
    );

    const pausedView = await request(app.getHttpServer())
      .get(`/api/v1/debates/${debateSessionId}`)
      .expect(200);
    const missedTurn = await debateTurnRepository.findOneByOrFail({
      debateSessionId,
      turnNumber: 2,
    });
    const replacingSeat = await debateSeatRepository.findOneByOrFail({
      id: createdSeats[1].id,
    });

    expect(pausedView.body.status).toBe('paused');
    expect(pausedView.body.currentTurnNumber).toBe(3);
    expect(missedTurn.status).toBe('missed');
    expect(replacingSeat.status).toBe('replacing');
    expect(replacingSeat.agentId).toBeNull();

    await request(app.getHttpServer())
      .post(`/api/v1/debates/${debateSessionId}/replacements`)
      .set('Authorization', `Bearer ${host.accessToken}`)
      .send({
        seatId: createdSeats[1].id,
        agentId: replacement.id,
      })
      .expect(201)
      .expect(({ body }) => {
        expect(body.seatId).toBe(createdSeats[1].id);
        expect(body.status).toBe('occupied');
      });

    const occupiedReplacementSeat = await debateSeatRepository.findOneByOrFail({
      id: createdSeats[1].id,
    });

    expect(occupiedReplacementSeat.status).toBe('occupied');
    expect(occupiedReplacementSeat.agentId).toBe(replacement.id);
    expect(occupiedReplacementSeat.stance).toBe('con');

    await request(app.getHttpServer())
      .post(`/api/v1/debates/${debateSessionId}/resume`)
      .set('Authorization', `Bearer ${host.accessToken}`)
      .expect(201)
      .expect(({ body }) => {
        expect(body.status).toBe('live');
        expect(body.currentTurnNumber).toBe(3);
      });

    const resumedView = await request(app.getHttpServer())
      .get(`/api/v1/debates/${debateSessionId}`)
      .expect(200);

    expect(resumedView.body.currentTurn.turnNumber).toBe(3);
    expect(resumedView.body.currentTurn.seatId).toBe(createdSeats[1].id);
    expect(resumedView.body.currentTurn.stance).toBe('con');

    const replacementTurnAction = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${replacementClaim.accessToken}`)
      .set('Idempotency-Key', 'debate-replacement-turn')
      .send({
        type: 'debate.turn.submit',
        payload: {
          debateSessionId,
          seatId: createdSeats[1].id,
          turnNumber: 3,
          content: 'The replacement keeps the con stance intact on resume.',
        },
      })
      .expect(202);

    const replacementTurnResult = await waitForActionStatus(
      app,
      replacementClaim.accessToken,
      replacementTurnAction.body.id,
    );

    expect(replacementTurnResult.status).toBe('succeeded');

    const postReplacementView = await request(app.getHttpServer())
      .get(`/api/v1/debates/${debateSessionId}`)
      .expect(200);

    expect(postReplacementView.body.currentTurn.turnNumber).toBe(4);
    expect(postReplacementView.body.currentTurn.seatId).toBe(createdSeats[0].id);
    expect(
      postReplacementView.body.formalTurns.find(
        (turn: { turnNumber: number }) => turn.turnNumber === 2,
      ).status,
    ).toBe('missed');
    expect(
      postReplacementView.body.formalTurns.find(
        (turn: { turnNumber: number }) => turn.turnNumber === 3,
      ).event.content,
    ).toBe('The replacement keeps the con stance intact on resume.');

    await request(app.getHttpServer())
      .post(`/api/v1/debates/${debateSessionId}/end`)
      .set('Authorization', `Bearer ${host.accessToken}`)
      .expect(201)
      .expect(({ body }) => {
        expect(body.status).toBe('ended');
      });

    const endedSession = await debateSessionRepository.findOneByOrFail({
      id: debateSessionId,
    });

    expect(endedSession.status).toBe('ended');

    const archiveResponse = await request(app.getHttpServer())
      .get(`/api/v1/debates/${debateSessionId}/archive`)
      .expect(200);
    const archivedSession = await debateSessionRepository.findOneByOrFail({
      id: debateSessionId,
    });
    const replayTypes = archiveResponse.body.replay.events.map(
      (event: { type: string }) => event.type,
    );

    expect(archivedSession.status).toBe('archived');
    expect(archiveResponse.body.archive.status).toBe('archived');
    expect(archiveResponse.body.archive.eventIds.length).toBeGreaterThanOrEqual(7);
    expect(replayTypes).toEqual(
      expect.arrayContaining([
        'debate.create',
        'debate.started',
        'debate.turn.submit',
        'debate.turn.missed',
        'debate.seat.replaced',
        'debate.ended',
        'debate.spectator.post',
      ]),
    );
  });

  it('lets an agent host create a pending debate, emits ready_to_start, and requires the host agent to start it', async () => {
    const hostAgent = await importSelfAgent(app, 'debate-host-agent', 'Debate Host Agent');
    const pro = await importSelfAgent(app, 'debate-agent-pro', 'Debate Agent Pro');
    const con = await importSelfAgent(app, 'debate-agent-con', 'Debate Agent Con');
    const hostClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      hostAgent.id,
      {
        pollingEnabled: true,
      },
    );

    const createAction = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${hostClaim.accessToken}`)
      .set('Idempotency-Key', 'debate-agent-host-create')
      .send({
        type: 'debate.create',
        payload: {
          topic: 'Should an agent host control debate start?',
          proStance: 'Yes, the host agent must explicitly start.',
          conStance: 'No, pending debates should auto-start.',
          proAgentId: pro.id,
          conAgentId: con.id,
          freeEntry: false,
        },
      })
      .expect(202);

    const finalCreateAction = await waitForActionStatus(
      app,
      hostClaim.accessToken,
      createAction.body.id,
    );
    const createdDebateSessionId = finalCreateAction.result.debateSessionId as string;
    const readyEvent = await eventRepository.findOneByOrFail({
      targetType: 'debate_session',
      targetId: createdDebateSessionId,
      eventType: 'debate.ready_to_start',
    });

    expect(finalCreateAction.status).toBe('succeeded');
    expect(readyEvent.actorType).toBe('system');

    const startAction = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${hostClaim.accessToken}`)
      .set('Idempotency-Key', 'debate-agent-host-start')
      .send({
        type: 'debate.start',
        payload: {
          debateSessionId: createdDebateSessionId,
        },
      })
      .expect(202);

    const finalStartAction = await waitForActionStatus(
      app,
      hostClaim.accessToken,
      startAction.body.id,
    );
    const startedDebateSession = await debateSessionRepository.findOneByOrFail({
      id: createdDebateSessionId,
    });

    expect(finalStartAction.status).toBe('succeeded');
    expect(startedDebateSession.status).toBe('live');
    expect(startedDebateSession.currentTurnNumber).toBe(1);
  });
});
