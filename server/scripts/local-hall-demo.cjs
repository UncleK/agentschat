// Opt-in, finite Hall demo. Uses the real debate lifecycle and turn validation.
// No model, external credentials or production database access.
const { DataSource, In } = require('typeorm');
const { AgentEntity } = require('../dist/src/database/entities/agent.entity');
const {
  DebateSessionEntity,
} = require('../dist/src/database/entities/debate-session.entity');
const { AuthService } = require('../dist/src/modules/auth/auth.service');
const { AgentsService } = require('../dist/src/modules/agents/agents.service');
const { DebateService } = require('../dist/src/modules/debate/debate.service');
const {
  ContentService,
} = require('../dist/src/modules/content/content.service');

async function startHallDemo(app) {
  const db = app.get(DataSource);
  const [{ name }] = await db.query('SELECT current_database() AS name');
  const target = new URL(process.env.DATABASE_URL);
  if (
    name !== 'agents_chat_preview' ||
    !['127.0.0.1', 'localhost', '[::1]'].includes(target.hostname)
  ) {
    throw new Error('Hall demo is restricted to the local preview database.');
  }
  const auth = app.get(AuthService);
  const identity = {
    email: 'hall-demo@example.test',
    username: 'local_hall_demo',
    displayName: '本地演示管理员',
    password: 'LocalReviewOnly2026!',
  };
  const exists = await db.query('SELECT id FROM users WHERE email=$1', [
    identity.email,
  ]);
  const { user } = exists.length
    ? await auth.loginWithEmail(identity)
    : await auth.registerWithEmail(identity);
  const actor = { type: 'human', id: user.id };
  const agents = app.get(AgentsService),
    debates = app.get(DebateService),
    content = app.get(ContentService);
  const repo = db.getRepository(AgentEntity);
  async function agent(handle, displayName, emoji, stance) {
    let value = await repo.findOneBy({ handle });
    if (value && value.ownerUserId !== user.id)
      throw new Error('Hall demo agent belongs to another owner.');
    if (!value)
      value = await agents.importHumanOwnedAgent(user, {
        handle,
        displayName,
        bio: `【本地演示】${stance}。由固定脚本驱动，用于检查大厅状态与辩论入口；不连接外部模型。`,
      });
    await repo.update(value.id, {
      profileTags: ['本地演示', '辩论'],
      runtimeName: '本地演示脚本',
      profileMetadata: { ...value.profileMetadata, avatarEmoji: emoji },
    });
    return value;
  }
  const pro = await agent(
    'local-demo-pro',
    'Nova · 演示正方',
    '✦',
    '支持先展示证据再讨论结论',
  );
  const con = await agent(
    'local-demo-con',
    'Vector · 演示反方',
    '⬡',
    '支持先表达观点再逐步核对证据',
  );
  const sessions = db.getRepository(DebateSessionEntity);
  // Reuse only this dedicated demo host's unfinished room after a restart.
  let room = await sessions.findOne({
    where: { hostUserId: user.id, status: In(['pending', 'live', 'paused']) },
    order: { createdAt: 'DESC' },
  });
  let id = room?.id;
  if (!id) {
    const created = await debates.createHumanHostedDebate(user, {
      topic: '【本地演示】Agent 交流应该先展示证据，还是先表达观点？',
      proStance: '先展示证据',
      conStance: '先表达观点',
      proAgentId: pro.id,
      conAgentId: con.id,
      freeEntry: false,
    });
    id = created.debateSessionId;
    room = await sessions.findOneByOrFail({ id });
  }
  if (room.status === 'pending') await debates.startDebate(actor, id);
  else if (room.status === 'paused') await debates.resumeDebate(actor, id);
  let timer,
    running,
    stopped = false;
  const started = Date.now();
  const lines = [
    '先把来源和适用范围说清楚，可以减少双方对同一句话的误解。',
    '观点也能帮助我们提出可检验的问题，证据可以随讨论逐步补充。',
    '赞同提出问题，同时应明确哪些结论已经验证、哪些仍是假设。',
    '那么可以把待验证的问题保留下来，让后续参与者继续核对。',
    '大厅的紫色状态应当对应正在进行的辩论，并能进入同一个房间。',
    '辩论结束后状态应当恢复，旁观者仍可查看留下的讨论记录。',
  ];
  async function tick() {
    const detail = await debates.getDebate(id);
    if (detail.status !== 'live') {
      stopped = true;
      return;
    }
    // One bounded hour per explicit invocation, within the normal turn limits.
    if (Date.now() - started >= 60 * 60 * 1000) {
      stopped = true;
      await debates.endDebate(actor, id);
      return;
    }
    const turn = detail.currentTurn;
    const seat = detail.seats.find((item) => item.id === turn?.seatId);
    if (!seat?.agent || ![pro.id, con.id].includes(seat.agent.id))
      throw new Error('Unexpected Hall demo seat.');
    await content.submitDebateTurn(seat.agent.id, {
      debateSessionId: id,
      turnNumber: turn.turnNumber,
      seatId: turn.seatId,
      content: `【本地脚本演示 · 第 ${turn.turnNumber} 回合】${lines[(turn.turnNumber - 1) % lines.length]}`,
    });
  }
  async function run() {
    try {
      await tick();
    } catch (error) {
      stopped = true;
      console.error('Hall demo stopped:', error.message);
      const detail = await debates.getDebate(id).catch(() => null);
      if (['live', 'paused'].includes(detail?.status))
        await debates.endDebate(actor, id);
    }
    if (!stopped)
      timer = setTimeout(() => {
        running = run();
      }, 20000);
  }
  running = run();
  await running;
  console.log(
    `Local scripted Hall demo: /live/${id} (ends after one hour; no external model)`,
  );
  return async () => {
    stopped = true;
    clearTimeout(timer);
    await running;
    const detail = await debates.getDebate(id);
    if (['live', 'paused'].includes(detail.status))
      await debates.endDebate(actor, id);
  };
}

module.exports = { startHallDemo };
