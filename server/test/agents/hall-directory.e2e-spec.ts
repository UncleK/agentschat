import request from 'supertest';
import {
  createTestApplication,
  type TestApplicationContext,
} from '../support/test-app';
import {
  importSelfAgent,
  registerHuman,
} from '../federation/support/federation-test-support';
import { DebateService } from '../../src/modules/debate/debate.service';
import { DebateSessionEntity } from '../../src/database/entities/debate-session.entity';
import { DebateSeatEntity } from '../../src/database/entities/debate-seat.entity';
import { ThreadEntity } from '../../src/database/entities/thread.entity';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import {
  AgentStatus,
  DebateSessionStatus,
  DebateSeatStatus,
  ThreadVisibility,
} from '../../src/database/domain.enums';

describe('Hall public room links', () => {
  let context: TestApplicationContext;
  beforeAll(async () => {
    context = await createTestApplication();
  });
  afterAll(async () => {
    await context?.close();
  });
  it('links an occupied live public room; never exposes private, paused, ended or vacated rooms', async () => {
    const { app, dataSource: db } = context;
    const owner = await registerHuman(
      app,
      'hall-link@example.test',
      'Hall Owner',
    );
    const pro = await importSelfAgent(app, 'hall-pro', 'Hall Pro');
    const con = await importSelfAgent(app, 'hall-con', 'Hall Con');
    const created = await app
      .get(DebateService)
      .createHumanHostedDebate(owner.user, {
        topic: 'Hall link regression',
        proStance: 'Pro',
        conStance: 'Con',
        proAgentId: pro.id,
        conAgentId: con.id,
      });
    const sessions = db.getRepository(DebateSessionEntity);
    const seats = db.getRepository(DebateSeatEntity);
    const threads = db.getRepository(ThreadEntity);
    const room = await sessions.findOneByOrFail({
      id: created.debateSessionId,
    });
    await sessions.update(room.id, { status: DebateSessionStatus.Live });
    await seats.update(
      { debateSessionId: room.id },
      { status: DebateSeatStatus.Occupied },
    );
    await db
      .getRepository(AgentEntity)
      .update([pro.id, con.id], { status: AgentStatus.Debating });
    const link = async () => {
      const response = await request(app.getHttpServer())
        .get('/api/v1/agents/public-directory')
        .expect(200);
      return (
        response.body.agents as Array<{
          id: string;
          liveDebateSessionId: string | null;
        }>
      ).find((a) => a.id === pro.id)?.liveDebateSessionId;
    };
    expect(await link()).toBe(room.id);
    await request(app.getHttpServer())
      .get('/api/v1/agents/public-directory/hall-pro')
      .expect(200)
      .expect(({ body }) =>
        expect(body.agent.liveDebateSessionId).toBe(room.id),
      );
    await threads.update(room.threadId, {
      visibility: ThreadVisibility.Private,
    });
    expect(await link()).toBeNull();
    await threads.update(room.threadId, {
      visibility: ThreadVisibility.Public,
    });
    for (const moderation of [{ hidden: true }, { deleted: true }]) {
      await threads.update(room.threadId, { metadata: { moderation } });
      expect(await link()).toBeNull();
    }
    await threads.update(room.threadId, { metadata: {} });
    expect(await link()).toBe(room.id);
    await seats.update(
      { debateSessionId: room.id, agentId: pro.id },
      { status: DebateSeatStatus.Vacant },
    );
    expect(await link()).toBeNull();
    await seats.update(
      { debateSessionId: room.id, agentId: pro.id },
      { status: DebateSeatStatus.Occupied },
    );
    for (const status of [
      DebateSessionStatus.Paused,
      DebateSessionStatus.Ended,
      DebateSessionStatus.Archived,
    ]) {
      await sessions.update(room.id, { status });
      expect(await link()).toBeNull();
    }
  });
});
