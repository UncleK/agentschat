import { randomUUID } from 'node:crypto';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { Repository } from 'typeorm';
import {
  DebateSeatStatus,
  DebateSessionStatus,
} from '../../src/database/domain.enums';
import { DebateSeatEntity } from '../../src/database/entities/debate-seat.entity';
import { DebateSessionEntity } from '../../src/database/entities/debate-session.entity';
import { DebateTurnEntity } from '../../src/database/entities/debate-turn.entity';
import { EventEntity } from '../../src/database/entities/event.entity';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import {
  TestApplicationContext,
  createTestApplication,
  typedValue,
} from '../support/test-app';
import {
  claimFederatedAgent,
  importSelfAgent,
  registerHuman,
  waitForActionStatus,
} from '../federation/support/federation-test-support';

interface ErrorMessageBody {
  message: string;
}

interface AcceptedActionBody {
  id: string;
}

interface DebateMutationBody {
  debateSessionId?: string;
  status: string;
  currentTurnNumber?: number;
  seatId?: string;
}

interface DebateViewBody {
  status: string;
  currentTurnNumber: number;
  currentTurn: {
    turnNumber: number;
    seatId: string;
    stance: string | null;
    deadlineAt: string | null;
  } | null;
  formalTurns: Array<{
    turnNumber: number;
    status: string;
    event: {
      content: string;
    } | null;
  }>;
  spectatorFeed: Array<{
    content: string;
  }>;
}

interface DebateArchiveBody {
  archive: {
    status: string;
    eventIds: string[];
  };
  replay: {
    events: Array<{
      type: string;
    }>;
  };
}

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
    debateSessionRepository =
      context.dataSource.getRepository(DebateSessionEntity);
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
      .expect(({ body }: { body: ErrorMessageBody }) => {
        expect(body.message).toMatch(/debate session/i);
      });

    await request(app.getHttpServer())
      .get(`/api/v1/debates/${missingDebateId}/archive`)
      .expect(404)
      .expect(({ body }: { body: ErrorMessageBody }) => {
        expect(body.message).toMatch(/debate session/i);
      });
  });

  it('enforces strict turns, separates spectators, pauses on a missed turn, and archives replay after end', async () => {
    const host = await registerHuman(
      app,
      'debate-host@example.com',
      'Debate Host',
    );
    const pro = await importSelfAgent(app, 'debate-pro', 'Debate Pro');
    const con = await importSelfAgent(app, 'debate-con', 'Debate Con');
    const replacement = await importSelfAgent(
      app,
      'debate-replacement',
      'Debate Replacement',
    );
    const spectator = await importSelfAgent(
      app,
      'debate-spectator',
      'Debate Spectator',
    );
    const proClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      pro.id,
      {
        pollingEnabled: true,
      },
    );
    const conClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      con.id,
      {
        pollingEnabled: true,
      },
    );
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
    const createBody = typedValue<DebateMutationBody>(createResponse.body);
    const debateSessionId = createBody.debateSessionId ?? '';
    const createdSeats = await debateSeatRepository.find({
      where: { debateSessionId },
      order: { seatOrder: 'ASC' },
    });

    expect(createBody.status).toBe('pending');
    expect(createdSeats).toHaveLength(2);
    expect(createdSeats[0].stance).toBe('pro');
    expect(createdSeats[1].stance).toBe('con');

    await request(app.getHttpServer())
      .post(`/api/v1/debates/${debateSessionId}/start`)
      .set('Authorization', `Bearer ${host.accessToken}`)
      .expect(201)
      .expect(({ body }: { body: DebateMutationBody }) => {
        expect(body.status).toBe('live');
        expect(body.currentTurnNumber).toBe(1);
      });

    const openingView = await request(app.getHttpServer())
      .get(`/api/v1/debates/${debateSessionId}`)
      .expect(200);
    const openingViewBody = typedValue<DebateViewBody>(openingView.body);

    expect(openingViewBody.currentTurn?.turnNumber).toBe(1);
    expect(openingViewBody.currentTurn?.seatId).toBe(createdSeats[0].id);
    expect(openingViewBody.currentTurn?.deadlineAt).toEqual(expect.any(String));
    const openingDeadlineMs = Date.parse(openingViewBody.currentTurn?.deadlineAt ?? '');
    expect(openingDeadlineMs - Date.now()).toBeGreaterThan(150_000);
    expect(openingDeadlineMs - Date.now()).toBeLessThanOrEqual(205_000);
    expect(openingViewBody.formalTurns).toHaveLength(1);
    expect(openingViewBody.spectatorFeed).toHaveLength(0);

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
    const outOfTurnActionBody = typedValue<AcceptedActionBody>(
      outOfTurnAction.body,
    );

    const outOfTurnResult = await waitForActionStatus(
      app,
      conClaim.accessToken,
      outOfTurnActionBody.id,
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
    const debaterSpectatorActionBody = typedValue<AcceptedActionBody>(
      debaterSpectatorAction.body,
    );

    const debaterSpectatorResult = await waitForActionStatus(
      app,
      proClaim.accessToken,
      debaterSpectatorActionBody.id,
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
    const spectatorActionBody = typedValue<AcceptedActionBody>(
      spectatorAction.body,
    );

    const spectatorResult = await waitForActionStatus(
      app,
      spectatorClaim.accessToken,
      spectatorActionBody.id,
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
          content:
            'Server-owned debate state is the only safe source of truth.',
        },
      })
      .expect(202);
    const openingTurnActionBody = typedValue<AcceptedActionBody>(
      openingTurnAction.body,
    );

    const openingTurnResult = await waitForActionStatus(
      app,
      proClaim.accessToken,
      openingTurnActionBody.id,
    );

    expect(openingTurnResult.status).toBe('succeeded');

    const afterOpeningTurn = await request(app.getHttpServer())
      .get(`/api/v1/debates/${debateSessionId}`)
      .expect(200);
    const afterOpeningTurnBody = typedValue<DebateViewBody>(
      afterOpeningTurn.body,
    );

    expect(afterOpeningTurnBody.currentTurn?.turnNumber).toBe(2);
    expect(afterOpeningTurnBody.currentTurn?.seatId).toBe(createdSeats[1].id);
    expect(afterOpeningTurnBody.spectatorFeed).toHaveLength(1);
    expect(afterOpeningTurnBody.spectatorFeed[0]?.content).toBe(
      'Spectators stay separate from formal turns.',
    );
    expect(
      afterOpeningTurnBody.formalTurns.find(
        (turn: { turnNumber: number }) => turn.turnNumber === 1,
      )?.event?.content,
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
    const pausedViewBody = typedValue<DebateViewBody>(pausedView.body);
    const missedTurn = await debateTurnRepository.findOneByOrFail({
      debateSessionId,
      turnNumber: 2,
    });
    const replacingSeat = await debateSeatRepository.findOneByOrFail({
      id: createdSeats[1].id,
    });

    expect(pausedViewBody.status).toBe('paused');
    expect(pausedViewBody.currentTurnNumber).toBe(3);
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
      .expect(({ body }: { body: DebateMutationBody }) => {
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
      .expect(({ body }: { body: DebateMutationBody }) => {
        expect(body.status).toBe('live');
        expect(body.currentTurnNumber).toBe(3);
      });

    const resumedView = await request(app.getHttpServer())
      .get(`/api/v1/debates/${debateSessionId}`)
      .expect(200);
    const resumedViewBody = typedValue<DebateViewBody>(resumedView.body);

    expect(resumedViewBody.currentTurn?.turnNumber).toBe(3);
    expect(resumedViewBody.currentTurn?.seatId).toBe(createdSeats[1].id);
    expect(resumedViewBody.currentTurn?.stance).toBe('con');

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
    const replacementTurnActionBody = typedValue<AcceptedActionBody>(
      replacementTurnAction.body,
    );

    const replacementTurnResult = await waitForActionStatus(
      app,
      replacementClaim.accessToken,
      replacementTurnActionBody.id,
    );

    expect(replacementTurnResult.status).toBe('succeeded');

    const postReplacementView = await request(app.getHttpServer())
      .get(`/api/v1/debates/${debateSessionId}`)
      .expect(200);
    const postReplacementViewBody = typedValue<DebateViewBody>(
      postReplacementView.body,
    );

    expect(postReplacementViewBody.currentTurn?.turnNumber).toBe(4);
    expect(postReplacementViewBody.currentTurn?.seatId).toBe(
      createdSeats[0].id,
    );
    expect(
      postReplacementViewBody.formalTurns.find(
        (turn: { turnNumber: number }) => turn.turnNumber === 2,
      )?.status,
    ).toBe('missed');
    expect(
      postReplacementViewBody.formalTurns.find(
        (turn: { turnNumber: number }) => turn.turnNumber === 3,
      )?.event?.content,
    ).toBe('The replacement keeps the con stance intact on resume.');

    await request(app.getHttpServer())
      .post(`/api/v1/debates/${debateSessionId}/end`)
      .set('Authorization', `Bearer ${host.accessToken}`)
      .expect(201)
      .expect(({ body }: { body: DebateMutationBody }) => {
        expect(body.status).toBe('ended');
      });

    const endedSession = await debateSessionRepository.findOneByOrFail({
      id: debateSessionId,
    });

    expect(endedSession.status).toBe('ended');

    const archiveResponse = await request(app.getHttpServer())
      .get(`/api/v1/debates/${debateSessionId}/archive`)
      .expect(200);
    const archiveBody = typedValue<DebateArchiveBody>(archiveResponse.body);
    const archivedSession = await debateSessionRepository.findOneByOrFail({
      id: debateSessionId,
    });
    const replayTypes = archiveBody.replay.events.map(
      (event: { type: string }) => event.type,
    );

    expect(archivedSession.status).toBe('archived');
    expect(archiveBody.archive.status).toBe('archived');
    expect(archiveBody.archive.eventIds.length).toBeGreaterThanOrEqual(7);
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

  it('accepts human-authenticated spectator comments through the public debate endpoint', async () => {
    const host = await registerHuman(
      app,
      'debate-human-spectator-host@example.com',
      'Debate Human Spectator Host',
    );
    const spectatorHuman = await registerHuman(
      app,
      'debate-human-spectator@example.com',
      'Debate Human Spectator',
    );
    const pro = await importSelfAgent(
      app,
      'debate-human-spectator-pro',
      'Debate Human Spectator Pro',
    );
    const con = await importSelfAgent(
      app,
      'debate-human-spectator-con',
      'Debate Human Spectator Con',
    );

    const createResponse = await request(app.getHttpServer())
      .post('/api/v1/debates')
      .set('Authorization', `Bearer ${host.accessToken}`)
      .send({
        topic: 'Should humans post spectator comments through HTTP?',
        proStance: 'Yes, the app needs a first-class spectator endpoint.',
        conStance: 'No, spectators should stay agent-only.',
        proAgentId: pro.id,
        conAgentId: con.id,
        freeEntry: true,
      })
      .expect(201);
    const createBody = typedValue<DebateMutationBody>(createResponse.body);
    const debateSessionId = createBody.debateSessionId ?? '';

    await request(app.getHttpServer())
      .post(`/api/v1/debates/${debateSessionId}/start`)
      .set('Authorization', `Bearer ${host.accessToken}`)
      .expect(201);

    await request(app.getHttpServer())
      .post(`/api/v1/debates/${debateSessionId}/spectator-comments`)
      .set('Authorization', `Bearer ${spectatorHuman.accessToken}`)
      .send({
        contentType: 'text',
        content: 'A human spectator can now comment through the app endpoint.',
      })
      .expect(201);

    const debateView = await request(app.getHttpServer())
      .get(`/api/v1/debates/${debateSessionId}`)
      .expect(200);
    const debateViewBody = typedValue<DebateViewBody>(debateView.body);

    expect(
      debateViewBody.spectatorFeed.map((event) => event.content),
    ).toContain('A human spectator can now comment through the app endpoint.');
  });

  it('lets an agent host create a pending debate, emits ready_to_start, and requires the host agent to start it', async () => {
    const hostAgent = await importSelfAgent(
      app,
      'debate-host-agent',
      'Debate Host Agent',
    );
    const pro = await importSelfAgent(
      app,
      'debate-agent-pro',
      'Debate Agent Pro',
    );
    const con = await importSelfAgent(
      app,
      'debate-agent-con',
      'Debate Agent Con',
    );
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
    const createActionBody = typedValue<AcceptedActionBody>(createAction.body);

    const finalCreateAction = await waitForActionStatus(
      app,
      hostClaim.accessToken,
      createActionBody.id,
    );
    const createdDebateSessionId = typedValue<{ debateSessionId: string }>(
      finalCreateAction.result,
    ).debateSessionId;
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
    const startActionBody = typedValue<AcceptedActionBody>(startAction.body);

    const finalStartAction = await waitForActionStatus(
      app,
      hostClaim.accessToken,
      startActionBody.id,
    );
    const startedDebateSession = await debateSessionRepository.findOneByOrFail({
      id: createdDebateSessionId,
    });

    expect(finalStartAction.status).toBe('succeeded');
    expect(startedDebateSession.status).toBe('live');
    expect(startedDebateSession.currentTurnNumber).toBe(1);
  });

  it('rejects agent-hosted debate creation when the host agent is also assigned to a seat', async () => {
    const hostAgent = await importSelfAgent(
      app,
      'debate-overlap-host-agent',
      'Debate Overlap Host',
    );
    const con = await importSelfAgent(
      app,
      'debate-overlap-con-agent',
      'Debate Overlap Con',
    );
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
      .set('Idempotency-Key', 'debate-agent-host-seat-overlap')
      .send({
        type: 'debate.create',
        payload: {
          topic: 'Should a host also take the pro seat?',
          proStance: 'Yes, one agent can do both.',
          conStance: 'No, the room needs three distinct roles.',
          proAgentId: hostAgent.id,
          conAgentId: con.id,
          freeEntry: false,
        },
      })
      .expect(202);
    const createActionBody = typedValue<AcceptedActionBody>(createAction.body);

    const finalCreateAction = await waitForActionStatus(
      app,
      hostClaim.accessToken,
      createActionBody.id,
    );

    expect(finalCreateAction.status).toBe('rejected');
    expect(finalCreateAction.error?.message).toMatch(
      /host agent cannot also occupy a pro or con seat/i,
    );
  });

  it('rejects assigning the host agent as a replacement debater', async () => {
    const hostAgent = await importSelfAgent(
      app,
      'debate-replacement-host-agent',
      'Debate Replacement Host',
    );
    const pro = await importSelfAgent(
      app,
      'debate-replacement-pro-agent',
      'Debate Replacement Pro',
    );
    const con = await importSelfAgent(
      app,
      'debate-replacement-con-agent',
      'Debate Replacement Con',
    );
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
      .set('Idempotency-Key', 'debate-agent-host-replacement-create')
      .send({
        type: 'debate.create',
        payload: {
          topic: 'Should a host agent enter as a replacement?',
          proStance: 'Yes, the host can fill the empty seat.',
          conStance: 'No, the host must remain separate from both seats.',
          proAgentId: pro.id,
          conAgentId: con.id,
          freeEntry: true,
        },
      })
      .expect(202);
    const createActionBody = typedValue<AcceptedActionBody>(createAction.body);

    const finalCreateAction = await waitForActionStatus(
      app,
      hostClaim.accessToken,
      createActionBody.id,
    );
    const createdDebateSessionId = typedValue<{ debateSessionId: string }>(
      finalCreateAction.result,
    ).debateSessionId;

    const proSeat = await debateSeatRepository.findOneByOrFail({
      debateSessionId: createdDebateSessionId,
      stance: 'pro',
    });
    await debateSessionRepository.update(
      { id: createdDebateSessionId },
      { status: DebateSessionStatus.Paused },
    );
    await debateSeatRepository.update(
      { id: proSeat.id },
      {
        status: DebateSeatStatus.Replacing,
        agentId: null,
      },
    );

    const resumeAction = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${hostClaim.accessToken}`)
      .set('Idempotency-Key', 'debate-agent-host-replacement-resume')
      .send({
        type: 'debate.resume',
        payload: {
          debateSessionId: createdDebateSessionId,
          seatId: proSeat.id,
          replacementAgentId: hostAgent.id,
        },
      })
      .expect(202);
    const resumeActionBody = typedValue<AcceptedActionBody>(resumeAction.body);

    const finalResumeAction = await waitForActionStatus(
      app,
      hostClaim.accessToken,
      resumeActionBody.id,
    );

    expect(finalResumeAction.status).toBe('rejected');
    expect(finalResumeAction.error?.message).toMatch(
      /host agent cannot also occupy a pro or con seat/i,
    );
  });

  it('auto-ends a live debate after the 24 hour duration cap', async () => {
    const host = await registerHuman(
      app,
      'debate-duration-host@example.com',
      'Debate Duration Host',
    );
    const pro = await importSelfAgent(app, 'debate-duration-pro', 'Duration Pro');
    const con = await importSelfAgent(app, 'debate-duration-con', 'Duration Con');

    const createResponse = await request(app.getHttpServer())
      .post('/api/v1/debates')
      .set('Authorization', `Bearer ${host.accessToken}`)
      .send({
        topic: 'Should long-running debates auto-end?',
        proStance: 'Yes, the service needs a hard ceiling.',
        conStance: 'No, the host should always decide manually.',
        proAgentId: pro.id,
        conAgentId: con.id,
        freeEntry: false,
      })
      .expect(201);
    const debateSessionId =
      typedValue<DebateMutationBody>(createResponse.body).debateSessionId ?? '';

    await request(app.getHttpServer())
      .post(`/api/v1/debates/${debateSessionId}/start`)
      .set('Authorization', `Bearer ${host.accessToken}`)
      .expect(201);

    await debateSessionRepository.update(
      { id: debateSessionId },
      {
        startedAt: new Date(Date.now() - 24 * 60 * 60 * 1000 - 5_000),
      },
    );

    const debateView = await request(app.getHttpServer())
      .get(`/api/v1/debates/${debateSessionId}`)
      .expect(200);
    const debateViewBody = typedValue<DebateViewBody>(debateView.body);
    const endedEvent = await eventRepository.findOneByOrFail({
      targetType: 'debate_session',
      targetId: debateSessionId,
      eventType: 'debate.ended',
    });

    expect(debateViewBody.status).toBe('ended');
    expect(endedEvent.actorType).toBe('system');
    expect(endedEvent.metadata).toMatchObject({
      reason: 'duration_limit_reached',
    });
  });

  it('auto-ends after the 200-per-side formal turn cap', async () => {
    const host = await registerHuman(
      app,
      'debate-turn-cap-host@example.com',
      'Debate Turn Cap Host',
    );
    const pro = await importSelfAgent(app, 'debate-turn-cap-pro', 'Turn Cap Pro');
    const con = await importSelfAgent(app, 'debate-turn-cap-con', 'Turn Cap Con');
    const proClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      pro.id,
      {
        pollingEnabled: true,
      },
    );

    const createResponse = await request(app.getHttpServer())
      .post('/api/v1/debates')
      .set('Authorization', `Bearer ${host.accessToken}`)
      .send({
        topic: 'Should debates stop after 200 turns per side?',
        proStance: 'Yes, a hard cap keeps things bounded.',
        conStance: 'No, debates should run until someone manually stops them.',
        proAgentId: pro.id,
        conAgentId: con.id,
        freeEntry: false,
      })
      .expect(201);
    const debateSessionId =
      typedValue<DebateMutationBody>(createResponse.body).debateSessionId ?? '';

    await request(app.getHttpServer())
      .post(`/api/v1/debates/${debateSessionId}/start`)
      .set('Authorization', `Bearer ${host.accessToken}`)
      .expect(201);

    const proSeat = await debateSeatRepository.findOneByOrFail({
      debateSessionId,
      stance: 'pro',
    });
    const currentTurn = await debateTurnRepository.findOneByOrFail({
      debateSessionId,
      turnNumber: 1,
    });

    await debateSessionRepository.update(
      { id: debateSessionId },
      {
        currentTurnNumber: 400,
      },
    );
    await debateTurnRepository.update(
      { id: currentTurn.id },
      {
        turnNumber: 400,
        seatId: proSeat.id,
        eventId: null,
        status: 'pending',
        deadlineAt: new Date(Date.now() + 60_000),
        submittedAt: null,
        metadata: {
          stance: 'pro',
          assignedAgentId: pro.id,
        },
      },
    );

    const submitAction = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${proClaim.accessToken}`)
      .set('Idempotency-Key', 'debate-turn-cap-submit')
      .send({
        type: 'debate.turn.submit',
        payload: {
          debateSessionId,
          seatId: proSeat.id,
          turnNumber: 400,
          content:
            'This is the final allowed formal turn before the debate auto-ends.',
        },
      })
      .expect(202);
    const submitActionBody = typedValue<AcceptedActionBody>(submitAction.body);

    const finalSubmitAction = await waitForActionStatus(
      app,
      proClaim.accessToken,
      submitActionBody.id,
    );
    const endedSession = await debateSessionRepository.findOneByOrFail({
      id: debateSessionId,
    });
    const endedEvent = await eventRepository.findOneByOrFail({
      targetType: 'debate_session',
      targetId: debateSessionId,
      eventType: 'debate.ended',
    });

    expect(finalSubmitAction.status).toBe('succeeded');
    expect(endedSession.status).toBe('ended');
    expect(endedSession.currentTurnNumber).toBe(400);
    expect(endedEvent.actorType).toBe('system');
    expect(endedEvent.metadata).toMatchObject({
      reason: 'turn_limit_reached',
      finalTurnNumber: 400,
    });
  });
});
