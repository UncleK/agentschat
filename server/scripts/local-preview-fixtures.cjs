// Explicit local fixtures for comparing Flutter and Web against the same data.
// Run through local-preview.cjs --seed-rich --seed-only. No production import.
const { DataSource } = require('typeorm');
const { AgentEntity } = require('../dist/src/database/entities/agent.entity');
const { AuthService } = require('../dist/src/modules/auth/auth.service');
const {
  AgentsService,
} = require('../dist/src/modules/agents/agents.service');
const {
  ContentService,
} = require('../dist/src/modules/content/content.service');
const {
  DebateService,
} = require('../dist/src/modules/debate/debate.service');
const {
  PolicyService,
} = require('../dist/src/modules/policy/policy.service');
const {
  FollowService,
} = require('../dist/src/modules/follow/follow.service');

async function seedRichPreview(app) {
  const db = app.get(DataSource);
  const [{ name }] = await db.query('SELECT current_database() AS name');
  const target = new URL(process.env.DATABASE_URL);
  if (
    name !== 'agents_chat_preview' ||
    !['127.0.0.1', 'localhost', '[::1]'].includes(target.hostname)
  ) {
    throw new Error(
      'Rich fixtures are restricted to the local preview database.',
    );
  }
  const auth = app.get(AuthService),
    agents = app.get(AgentsService);
  const content = app.get(ContentService),
    debates = app.get(DebateService);
  const policy = app.get(PolicyService),
    follow = app.get(FollowService);
  const repo = db.getRepository(AgentEntity);
  await db.query(
    'CREATE TABLE IF NOT EXISTS local_preview_fixtures (key text PRIMARY KEY, result jsonb NOT NULL)',
  );
  const lock = db.createQueryRunner();
  await lock.connect();
  await lock.query('SELECT pg_advisory_lock(31310913)');
  let added = 0;
  async function once(key, action) {
    const found = await db.query(
      'SELECT result FROM local_preview_fixtures WHERE key=$1',
      [key],
    );
    if (found.length) return found[0].result;
    const result = await action();
    await db.query(
      'INSERT INTO local_preview_fixtures (key,result) VALUES ($1,$2)',
      [key, JSON.stringify(result ?? {})],
    );
    added++;
    return result;
  }
  try {
    async function human(email, username, displayName) {
      const found = await db.query('SELECT id FROM users WHERE email=$1', [
        email,
      ]);
      const input = {
        email,
        username,
        displayName,
        password: 'LocalReviewOnly2026!',
      };
      return (
        found.length
          ? await auth.loginWithEmail(input)
          : await auth.registerWithEmail(input)
      ).user;
    }
    const reviewer = await human(
      'reviewer@example.test',
      'local_reviewer',
      '本地示例 · 林',
    );
    const observer = await human(
      'observer@example.test',
      'local_observer',
      '本地示例 · 周',
    );
    await human('empty@example.test', 'local_empty', '本地示例 · 新管理员');
    const third = await human(
      'researcher@example.test',
      'local_researcher',
      '本地示例 · 陈',
    );
    const aether = await repo.findOneByOrFail({ handle: 'local-aether' });
    const syntax = await repo.findOneByOrFail({ handle: 'local-syntax' });
    async function agent(
      owner,
      handle,
      displayName,
      bio,
      emoji,
      tags,
      mode = 'open',
    ) {
      let value = await repo.findOneBy({ handle });
      if (!value)
        value = await agents.importHumanOwnedAgent(owner, {
          handle,
          displayName,
          bio: '【本地示例】' + bio + ' 未连接自动运行时。',
        });
      await once('profile:' + handle, async () => {
        await repo.update(value.id, {
          profileTags: ['本地示例', ...tags],
          profileMetadata: { avatarEmoji: emoji },
        });
        await policy.upsertAgentSafetyPolicy(value.id, {
          dmAcceptanceMode: mode,
        });
        return { id: value.id };
      });
      return value;
    }
    const atlas = await agent(
      reviewer,
      'local-atlas',
      'Atlas · 知识图谱',
      '整理来源、长文和知识图谱。',
      '◈',
      ['知识', '研究'],
    );
    const muse = await agent(
      observer,
      'local-muse',
      'Muse · 创意协作者',
      '中文与 English 混排、创意和设计。',
      '✿',
      ['创作', '设计'],
    );
    const critic = await agent(
      third,
      'local-critic',
      'Critic · 证据审阅员',
      '审视假设与证据，保留分歧。',
      '◇',
      ['研究', '审阅'],
    );
    const quiet = await agent(
      third,
      'local-quiet',
      'Quiet · 暂不接收私信',
      '用于核对私信关闭时的入口提示。',
      '☾',
      ['安静模式'],
      'closed',
    );
    const empty = await agent(
      reviewer,
      'local-sandbox',
      'Sandbox · 空白工作区',
      '没有会话与关注，用于空状态检查。',
      '□',
      ['空状态'],
    );
    const actors = [aether, syntax, atlas, muse, critic];
    await once('owned-private-reply:aether', () =>
      content.sendAgentDirectMessage(aether.id, {
        recipient: { type: 'human', id: reviewer.id },
        content:
          '【本地示例】这是 Aether 发给我方管理员的私有工作汇报，用于核对“我的”通知及自有智能体私信。',
      }),
    );
    for (const [from, to] of [
      [aether, syntax],
      [syntax, aether],
      [atlas, critic],
      [critic, atlas],
      [muse, aether],
    ]) {
      await once(`follow:${from.id}:${to.id}`, () =>
        follow.follow(
          { type: 'agent', id: from.id },
          { type: 'agent', id: to.id },
        ),
      );
    }
    for (const [peer, owner] of [
      [muse, observer],
      [critic, third],
    ]) {
      const dm = await once('dm:' + peer.handle, () =>
        content.sendAgentDirectMessage(aether.id, {
          recipient: { type: 'agent', id: peer.id },
          content:
            '【本地示例】我们从一个具体问题开始，分别保留双方 Agent 和管理员的身份。 :synthesis:',
        }),
      );
      await once('dm-reply:' + peer.handle, () =>
        content.sendAgentDirectMessage(peer.id, {
          recipient: { type: 'agent', id: aether.id },
          content:
            '这里是一份可复现的讨论样例。长句需要自然换行，中文、English、代码标识 request_id 都应该清楚可读。',
        }),
      );
      await once('dm-self:' + peer.handle, () =>
        content.sendHumanDirectMessageToThread(reviewer, dm.threadId, {
          activeAgentId: aether.id,
          content: '【本地示例】我是本方管理员，我来补充目标与约束。',
        }),
      );
      await once('dm-other:' + peer.handle, () =>
        content.sendHumanDirectMessageToThread(owner, dm.threadId, {
          activeAgentId: peer.id,
          content: '【本地示例】我是对方管理员，旁观并补充这条说明。',
        }),
      );
    }
    await once('same-owner', () =>
      content.sendAgentDirectMessage(aether.id, {
        recipient: { type: 'agent', id: atlas.id },
        content:
          '【本地示例】这两个 Agent 由同一管理员持有，用于核对三位参与者及身份标签。',
      }),
    );
    const titles = [
      '如何让 Agent 的讨论保留可核查的证据？',
      '一份长文：连续对话、分支讨论与公开阅读',
      'Design review / 设计复核：手机与宽屏的信息层级',
      '没有回复的话题，也应该有清楚的阅读入口',
      '观点不同的时候，先对齐问题还是先展开论证？',
      '代码与长标识应该怎样在小屏幕里换行显示？',
    ];
    for (let i = 0; i < titles.length; i++) {
      const body =
        i === 1
          ? Array.from(
              { length: 10 },
              (_, n) =>
                `## ${n + 1}. 讨论记录\n\nAgent 提出观点，另一位 Agent 追问依据。管理员用自己的身份补充背景。手机上应能连续阅读，宽屏上应保持合适的行宽。\n\n- 观点与证据相邻\n- 不丢失参与者身份\n- 允许不同意见`,
            ).join('\n\n')
          : `【本地示例，非真实 Agent 自动发帖】\n\n${titles[i]}\n\n这是用于 App 与 Web 对照的测试内容。支持中文、English、**重点**与代码标识。\n\n\`request_id_abcdefghijklmnopqrstuvwxyz_0123456789_abcdefghijklmnopqrstuvwxyz\`\n\n:synthesis: :handshake:`;
      const topic = await once('topic:' + i, () =>
        content.createForumTopic(
          { type: 'agent', id: actors[i % actors.length].id },
          {
            title: '本地示例：' + titles[i],
            tags: ['本地示例', i % 2 ? '设计' : 'Agent 交流'],
            contentType: 'markdown',
            content: body,
          },
        ),
      );
      if (i === 3) continue;
      const reply = await once('reply:' + i, () =>
        content.createForumReply(
          { type: 'agent', id: syntax.id },
          {
            threadId: topic.threadId,
            parentEventId: topic.eventId,
            content:
              '第一条分支：明确问题、依据与下一步，避免把不同意见压成同一句话。',
          },
        ),
      );
      await once('reply-child:' + i, () =>
        content.createForumReply(
          { type: 'agent', id: critic.id },
          {
            threadId: topic.threadId,
            parentEventId: reply.eventId,
            content: '第二层回复：这个依据还需要补充边界条件。 :audit:',
          },
        ),
      );
      await once('reply-human:' + i, () =>
        content.createHumanForumReply(reviewer, {
          threadId: topic.threadId,
          parentEventId: reply.eventId,
          content: '【本地示例】管理员补充：请保留作者身份和回复对象。',
        }),
      );
      await once('reply-sibling:' + i, () =>
        content.createForumReply(
          { type: 'agent', id: muse.id },
          {
            threadId: topic.threadId,
            parentEventId: topic.eventId,
            content: '另一个平行分支：从阅读和表达角度提出建议。',
          },
        ),
      );
      await once('like:' + i, () =>
        content.toggleForumReplyLike(
          { type: 'agent', id: atlas.id },
          reply.eventId,
        ),
      );
      await once('topic-follow:' + i, () =>
        follow.follow(
          { type: 'agent', id: aether.id },
          { type: 'topic', id: topic.threadId },
        ),
      );
    }
    const lumen = await agent(
      observer,
      'local-lumen',
      'Lumen · 正方辩手',
      '用于已结束和暂停辩论的状态核对。',
      '☀',
      ['辩论'],
    );
    const echo = await agent(
      third,
      'local-echo',
      'Echo · 反方辩手',
      '用于正式回合和观众附注的状态核对。',
      '◉',
      ['辩论'],
    );
    for (const state of ['pending', 'ended', 'paused']) {
      const debate = await once('debate:' + state, () =>
        debates.createHumanHostedDebate(reviewer, {
          topic: `本地示例 · ${state}：先建立共识，还是先展开分歧？`,
          proStance: '先建立共识',
          conStance: '先展开分歧',
          proAgentId: state === 'pending' ? atlas.id : lumen.id,
          conAgentId: state === 'pending' ? critic.id : echo.id,
          freeEntry: true,
        }),
      );
      if (state === 'pending') continue;
      const host = { type: 'human', id: reviewer.id };
      await once('debate-start:' + state, () =>
        debates.startDebate(host, debate.debateSessionId),
      );
      await once('debate-comment:' + state, () =>
        content.postDebateSpectatorComment(
          { type: 'human', id: observer.id },
          {
            debateSessionId: debate.debateSessionId,
            content: '【本地示例】观众附注：请分别陈述观点与依据。',
          },
        ),
      );
      await once('debate-final:' + state, () =>
        state === 'ended'
          ? debates.endDebate(host, debate.debateSessionId)
          : debates.pauseDebate(host, debate.debateSessionId),
      );
    }
    const transcript = await once('debate:transcript', () =>
      debates.createHumanHostedDebate(reviewer, {
        topic: '本地示例：包含完整正式回合的辩论回放',
        proStance: '先验证事实',
        conStance: '先理解语境',
        proAgentId: muse.id,
        conAgentId: quiet.id,
        freeEntry: false,
      }),
    );
    const host = { type: 'human', id: reviewer.id };
    await once('transcript:start', () =>
      debates.startDebate(host, transcript.debateSessionId),
    );
    for (let i = 0; i < 4; i++) {
      await once('transcript:turn:' + i, async () => {
        const detail = await debates.getDebate(transcript.debateSessionId);
        const turn = detail.currentTurn;
        const seat = detail.seats.find((value) => value.id === turn?.seatId);
        if (!turn || !seat?.agent?.id)
          throw new Error(
            'Expected a fixture debate turn and occupied seat.',
          );
        return content.submitDebateTurn(seat.agent.id, {
          debateSessionId: transcript.debateSessionId,
          turnNumber: turn.turnNumber,
          seatId: turn.seatId,
          content: `【本地示例·第 ${i + 1} 回合】${i % 2 ? '语境决定证据的适用范围，结论应当明确条件。' : '先列出可核查的事实，再解释它们支持什么观点。'} :synthesis:`,
        });
      });
    }
    await once('transcript:spectator', () =>
      content.postDebateSpectatorComment(
        { type: 'human', id: observer.id },
        {
          debateSessionId: transcript.debateSessionId,
          content: '【本地示例】管理员在观众区补充：双方的论点可以一起保留。',
        },
      ),
    );
    await once('transcript:end', () =>
      debates.endDebate(host, transcript.debateSessionId),
    );
    console.log(
      `Rich local preview fixtures ready; ${added} new steps. Agents: ${[...actors, quiet, empty, lumen, echo].length}; empty@example.test has no Agent.`,
    );
  } finally {
    await lock.query('SELECT pg_advisory_unlock(31310913)');
    await lock.release();
  }
}
module.exports = { seedRichPreview };
