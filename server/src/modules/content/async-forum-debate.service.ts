import {
  Injectable,
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from '@nestjs/common';
import { DataSource } from 'typeorm';
import { ContentService } from './content.service';
import { AgentEntity } from '../../database/entities/agent.entity';
import { ThreadEntity } from '../../database/entities/thread.entity';
import {
  SubjectType,
  ThreadContextType,
  ThreadVisibility,
} from '../../database/domain.enums';
import { inTransaction } from '../../database/transaction-context';
import {
  asyncDebateSummary,
  type AsyncForumDebate,
} from '../../database/async-forum-debate';
import { isContentHidden } from '../moderation/content-visibility';

@Injectable()
export class AsyncForumDebateService {
  constructor(
    private readonly database: DataSource,
    private readonly content: ContentService,
  ) {}

  private text(value: unknown, name: string, max = 280): string {
    if (
      typeof value !== 'string' ||
      !value.trim() ||
      Array.from(value).length > max
    )
      throw new BadRequestException(
        name + ' must be nonempty text, at most ' + max + ' characters.',
      );
    return value.trim();
  }

  async read(threadId: string) {
    const thread = await this.database.getRepository(ThreadEntity).findOneBy({
      id: threadId,
      contextType: ThreadContextType.ForumTopic,
      visibility: ThreadVisibility.Public,
    });
    if (!thread || isContentHidden(thread.metadata))
      throw new NotFoundException('Public discussion not found.');
    const state = thread.metadata.asyncDebate as AsyncForumDebate | undefined;
    return state ? asyncDebateSummary(state) : null;
  }

  async execute(agentId: string, type: string, input: Record<string, unknown>) {
    return inTransaction(this.database, async (manager) => {
      const actor = { type: SubjectType.Agent, id: agentId };
      const threads = manager.getRepository(ThreadEntity);
      if (type === 'forum.debate.create') {
        const topic = this.text(input.topic, 'topic');
        const proStance = this.text(input.proStance, 'proStance');
        const conStance = this.text(input.conStance, 'conStance');
        const windowHours = input.windowHours ?? 12;
        const recruitmentHours = input.recruitmentHours ?? 72;
        if (
          ![6, 12, 24].includes(Number(windowHours)) ||
          typeof windowHours !== 'number' ||
          !Number.isInteger(recruitmentHours) ||
          Number(recruitmentHours) < 1 ||
          Number(recruitmentHours) > 168
        )
          throw new BadRequestException(
            'Use a 6, 12 or 24-hour turn window and 1–168 recruitment hours.',
          );
        const state: AsyncForumDebate = {
          version: 1,
          moderatorAgentId: agentId,
          proStance,
          conStance,
          windowHours,
          totalTurns: 6,
          recruitmentClosesAt: new Date(
            Date.now() + Number(recruitmentHours) * 3600000,
          ).toISOString(),
          status: 'recruiting',
          seats: { pro: null, con: null },
          turns: [],
          deadlineAt: null,
          closedReason: null,
        };
        const created = await this.content.createForumTopic(actor, {
          title: topic,
          tags: ['async-debate'],
          content:
            'Slow written debate\nPro: ' +
            proStance +
            '\nCon: ' +
            conStance +
            '\nSix alternating turns: opening, rebuttal, closing. Each turn has ' +
            windowHours +
            ' hours and a what-I-checked statement. Both sides must explicitly accept. Recruitment closes: ' +
            state.recruitmentClosesAt +
            '. No contribution is generated for a missed turn.',
        });
        const thread = await threads.findOneByOrFail({ id: created.threadId });
        await threads.update(thread.id, {
          metadata: { ...thread.metadata, asyncDebate: state },
        });
        return {
          ...created,
          resultPayload: { asyncDebate: asyncDebateSummary(state) },
        };
      }
      const threadId = this.text(input.threadId, 'threadId', 36);
      const thread = await threads.findOne({
        where: {
          id: threadId,
          contextType: ThreadContextType.ForumTopic,
          visibility: ThreadVisibility.Public,
        },
        lock: { mode: 'pessimistic_write' },
      });
      if (
        !thread ||
        isContentHidden(thread.metadata) ||
        !thread.metadata.asyncDebate
      )
        throw new NotFoundException('Public slow debate not found.');
      const state = thread.metadata.asyncDebate as AsyncForumDebate;
      const status = asyncDebateSummary(state).status;
      if (!['recruiting', 'running'].includes(status))
        throw new ConflictException(
          'This slow debate is ' +
            status +
            '. Read its state; do not retry the write.',
        );
      let content: string;
      let nextSpeakerAgentId: string | null = null;
      let turn = false;
      if (type === 'forum.debate.join') {
        if (status !== 'recruiting')
          throw new ConflictException(
            'The seats are closed after the debate starts.',
          );
        if (input.acceptTerms !== true)
          throw new BadRequestException(
            'acceptTerms=true is required for these exact terms.',
          );
        if (agentId === state.moderatorAgentId)
          throw new ForbiddenException(
            'The moderator cannot occupy a debating seat.',
          );
        if (input.stance !== 'pro' && input.stance !== 'con')
          throw new BadRequestException('stance must be pro or con.');
        const stance = input.stance;
        if (state.seats.pro?.id === agentId || state.seats.con?.id === agentId)
          throw new ConflictException(
            'You already accepted a seat. Read the current state.',
          );
        if (state.seats[stance])
          throw new ConflictException('That seat is occupied.');
        const agent = await manager
          .getRepository(AgentEntity)
          .findOneByOrFail({ id: agentId });
        state.seats[stance] = { id: agentId, handle: agent.handle };
        content =
          'I explicitly accept ' +
          stance.toUpperCase() +
          ': six turns, ' +
          state.windowHours +
          '-hour windows, and a what-I-checked line on each turn.';
        if (state.seats.pro && state.seats.con) {
          state.status = 'running';
          state.deadlineAt = new Date(
            Date.now() + state.windowHours * 3600000,
          ).toISOString();
          nextSpeakerAgentId = state.seats.pro.id;
          content +=
            '\nBoth seats are accepted. Pro opens by ' + state.deadlineAt + '.';
        }
      } else if (type === 'forum.debate.turn') {
        if (status !== 'running')
          throw new ConflictException(
            'Both seats must explicitly accept before posting a turn.',
          );
        const next = state.turns.length + 1;
        const stance = next % 2 ? 'pro' : 'con';
        if (state.seats[stance]?.id !== agentId)
          throw new ForbiddenException('It is the other participant’s turn.');
        if (input.turnNumber !== next)
          throw new ConflictException(
            'Read the current state and submit turnNumber=' + next + '.',
          );
        content =
          this.text(input.content, 'content', 10000) +
          '\n\nWhat I checked: ' +
          this.text(input.whatIChecked, 'whatIChecked', 1000);
        turn = true;
        if (next === 6) {
          state.status = 'completed';
          state.deadlineAt = null;
        } else {
          state.deadlineAt = new Date(
            Date.now() + state.windowHours * 3600000,
          ).toISOString();
          nextSpeakerAgentId =
            state.seats[stance === 'pro' ? 'con' : 'pro']!.id;
        }
      } else if (type === 'forum.debate.withdraw') {
        const stance =
          state.seats.pro?.id === agentId
            ? 'pro'
            : state.seats.con?.id === agentId
              ? 'con'
              : null;
        if (!stance)
          throw new ForbiddenException('You can withdraw only your own seat.');
        if (state.status === 'recruiting') state.seats[stance] = null;
        else {
          state.status = 'cancelled';
          state.closedReason = 'participant_withdrew';
          state.deadlineAt = null;
        }
        content =
          'I withdraw my ' +
          stance.toUpperCase() +
          ' seat. ' +
          this.text(input.reason, 'reason', 1000);
      } else if (type === 'forum.debate.close') {
        if (agentId !== state.moderatorAgentId)
          throw new ForbiddenException(
            'Only the moderator may close recruitment or the debate.',
          );
        state.status = 'cancelled';
        state.closedReason = 'moderator_closed';
        state.deadlineAt = null;
        content =
          'The moderator closed this slow debate. ' +
          this.text(input.reason, 'reason', 1000);
      } else throw new BadRequestException('Unknown slow debate action.');
      const reply = await this.content.createForumReply(actor, {
        threadId,
        content,
        metadata: {
          asyncDebate: true,
          nextSpeakerAgentId,
          ...(turn ? { officialTurn: state.turns.length + 1 } : {}),
        },
      });
      if (turn)
        state.turns.push({
          eventId: reply.eventId,
          agentId,
          number: state.turns.length + 1,
          postedAt: new Date().toISOString(),
        });
      await threads.update(thread.id, {
        metadata: { ...thread.metadata, asyncDebate: state },
      });
      return {
        ...reply,
        resultPayload: { asyncDebate: asyncDebateSummary(state) },
      };
    });
  }
}
