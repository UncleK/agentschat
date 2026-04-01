import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, EntityManager, Repository } from 'typeorm';
import {
  AgentStatus,
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
} from '../../database/domain.enums';
import { AgentEntity } from '../../database/entities/agent.entity';
import { DebateSeatEntity } from '../../database/entities/debate-seat.entity';
import { DebateSessionEntity } from '../../database/entities/debate-session.entity';
import { DebateTurnEntity } from '../../database/entities/debate-turn.entity';
import { EventEntity } from '../../database/entities/event.entity';
import { ThreadParticipantEntity } from '../../database/entities/thread-participant.entity';
import { ThreadEntity } from '../../database/entities/thread.entity';
import type { AuthenticatedHuman } from '../auth/auth.types';
import { ModerationService } from '../moderation/moderation.service';
import { NotificationsService } from '../notifications/notifications.service';

interface DebateActor {
  type: SubjectType;
  id: string;
}

interface CreateDebateInput {
  topic?: string | null;
  proStance?: string | null;
  conStance?: string | null;
  proAgentId?: string | null;
  conAgentId?: string | null;
  freeEntry?: unknown;
  humanHostAllowed?: unknown;
  hostType?: string | null;
  hostId?: string | null;
  hostAgentId?: string | null;
}

interface AssignReplacementInput {
  debateSessionId: string;
  seatId?: string | null;
  agentId?: string | null;
}

interface PreparedTurnSubmission {
  debateSession: DebateSessionEntity;
  seat: DebateSeatEntity;
  debateTurn: DebateTurnEntity;
}

@Injectable()
export class DebateService {
  private readonly defaultTurnDeadlineMs = 60_000;

  constructor(
    private readonly dataSource: DataSource,
    @InjectRepository(AgentEntity)
    private readonly agentRepository: Repository<AgentEntity>,
    @InjectRepository(ThreadEntity)
    private readonly threadRepository: Repository<ThreadEntity>,
    @InjectRepository(ThreadParticipantEntity)
    private readonly threadParticipantRepository: Repository<ThreadParticipantEntity>,
    @InjectRepository(EventEntity)
    private readonly eventRepository: Repository<EventEntity>,
    @InjectRepository(DebateSessionEntity)
    private readonly debateSessionRepository: Repository<DebateSessionEntity>,
    @InjectRepository(DebateSeatEntity)
    private readonly debateSeatRepository: Repository<DebateSeatEntity>,
    @InjectRepository(DebateTurnEntity)
    private readonly debateTurnRepository: Repository<DebateTurnEntity>,
    private readonly moderationService: ModerationService,
    private readonly notificationsService: NotificationsService,
  ) {}

  async createHumanHostedDebate(
    human: AuthenticatedHuman,
    input: CreateDebateInput,
  ) {
    await this.moderationService.assertActorAllowed({
      type: SubjectType.Human,
      id: human.id,
    });

    const hostType = this.optionalString(input.hostType)?.toLowerCase();

    if (hostType && hostType !== SubjectType.Human) {
      throw new BadRequestException(
        'Human-authenticated debate creation only supports a human host.',
      );
    }

    return this.createDebate(
      {
        type: SubjectType.Human,
        id: human.id,
      },
      input,
      true,
    );
  }

  async createAgentHostedDebate(actorAgentId: string, input: CreateDebateInput) {
    await this.moderationService.assertActorAllowed({
      type: SubjectType.Agent,
      id: actorAgentId,
    });

    const hostType = this.optionalString(input.hostType)?.toLowerCase();
    const hostAgentId = this.optionalString(input.hostAgentId ?? input.hostId);

    if (hostType && hostType !== SubjectType.Agent) {
      throw new ConflictException(
        'Federated debate creation requires the acting agent to be the host.',
      );
    }

    if (hostAgentId && hostAgentId !== actorAgentId) {
      throw new ConflictException(
        'Federated debate creation requires the acting agent to match the host.',
      );
    }

    return this.createDebate(
      {
        type: SubjectType.Agent,
        id: actorAgentId,
      },
      input,
      this.optionalBoolean(input.humanHostAllowed) ?? false,
    );
  }

  async getDebate(debateSessionId: string) {
    await this.sweepDebateSession(debateSessionId);

    const debateSession = await this.debateSessionRepository.findOneBy({
      id: debateSessionId,
    });

    if (!debateSession) {
      throw new NotFoundException(`Debate session ${debateSessionId} was not found.`);
    }

    const [seats, turns, spectatorFeed] = await Promise.all([
      this.debateSeatRepository.find({
        where: { debateSessionId },
        order: { seatOrder: 'ASC' },
      }),
      this.debateTurnRepository.find({
        where: { debateSessionId },
        order: { turnNumber: 'ASC' },
        relations: {
          event: true,
        },
      }),
      this.eventRepository.find({
        where: {
          threadId: debateSession.threadId,
          eventType: 'debate.spectator.post',
        },
        order: {
          occurredAt: 'ASC',
        },
      }),
    ]);

    const currentTurn = turns.find(
      (turn) =>
        turn.turnNumber === debateSession.currentTurnNumber &&
        turn.status === DebateTurnStatus.Pending,
    );

    return {
      debateSessionId: debateSession.id,
      threadId: debateSession.threadId,
      topic: debateSession.topic,
      proStance: debateSession.proStance,
      conStance: debateSession.conStance,
      host: this.serializeHost(debateSession),
      status: debateSession.status,
      freeEntry: debateSession.freeEntry,
      humanHostAllowed: debateSession.humanHostAllowed,
      currentTurnNumber: debateSession.currentTurnNumber,
      archivedAt: debateSession.archivedAt?.toISOString() ?? null,
      seats: seats.map((seat) => this.serializeSeat(seat)),
      currentTurn: currentTurn
        ? this.serializeTurn(currentTurn, seats)
        : null,
      formalTurns: turns.map((turn) => this.serializeTurn(turn, seats)),
      spectatorFeed: spectatorFeed.map((event) => this.serializeEvent(event)),
    };
  }

  async getDebateArchive(debateSessionId: string) {
    const debateSession = await this.debateSessionRepository.findOneBy({
      id: debateSessionId,
    });

    if (!debateSession) {
      throw new NotFoundException(`Debate session ${debateSessionId} was not found.`);
    }

    if (debateSession.status === DebateSessionStatus.Ended) {
      await this.moderationService.archiveDebateSession(debateSessionId, {
        archivedByLifecycle: true,
      });
    }

    return this.moderationService.readDebateArchive(debateSessionId);
  }

  async startDebate(actor: DebateActor, debateSessionId: string) {
    await this.moderationService.assertActorAllowed(actor);

    const result = await this.dataSource.transaction(async (manager) => {
      const debateSessionRepository = manager.getRepository(DebateSessionEntity);
      const debateSession = await debateSessionRepository.findOneBy({
        id: debateSessionId,
      });

      if (!debateSession) {
        throw new NotFoundException(`Debate session ${debateSessionId} was not found.`);
      }

      this.assertHostActor(debateSession, actor);

      if (debateSession.status !== DebateSessionStatus.Pending) {
        throw new ConflictException('Only pending debates can be started.');
      }

      const seats = await this.loadSeats(manager, debateSession.id);

      if (seats.length !== 2 || seats.some((seat) => !seat.agentId || seat.status !== DebateSeatStatus.Occupied)) {
        throw new ConflictException(
          'A debate requires exactly two occupied seats before it can go live.',
        );
      }

      const debateTurn = await this.ensurePendingTurn(
        manager,
        debateSession,
        seats,
        debateSession.currentTurnNumber,
      );

      await debateSessionRepository.update(
        { id: debateSession.id },
        {
          status: DebateSessionStatus.Live,
          currentTurnNumber: debateTurn.turnNumber,
        },
      );

      const startedEvent = await this.createDebateEvent(
        manager,
        debateSession,
        'debate.started',
        this.bindActor(actor),
        {
          currentTurnNumber: debateTurn.turnNumber,
        },
      );
      const assignedEvent = await this.createTurnAssignedEvent(
        manager,
        debateSession,
        debateTurn,
        seats,
      );

      return {
        debateSessionId: debateSession.id,
        threadId: debateSession.threadId,
        status: DebateSessionStatus.Live,
        currentTurnNumber: debateTurn.turnNumber,
        eventId: startedEvent.id,
        followUpEventIds: [assignedEvent.id],
        touchedAgentIds: seats
          .map((seat) => seat.agentId)
          .filter((agentId): agentId is string => Boolean(agentId)),
      };
    });

    await this.processEventIds([result.eventId, ...result.followUpEventIds]);
    await this.syncAgentStatuses(result.touchedAgentIds);

    return result;
  }

  async pauseDebate(actor: DebateActor, debateSessionId: string, reason?: string | null) {
    await this.moderationService.assertActorAllowed(actor);
    await this.sweepDebateSession(debateSessionId);

    const result = await this.dataSource.transaction(async (manager) => {
      const debateSessionRepository = manager.getRepository(DebateSessionEntity);
      const debateSession = await debateSessionRepository.findOneBy({
        id: debateSessionId,
      });

      if (!debateSession) {
        throw new NotFoundException(`Debate session ${debateSessionId} was not found.`);
      }

      this.assertHostActor(debateSession, actor);

      if (debateSession.status !== DebateSessionStatus.Live) {
        throw new ConflictException('Only live debates can be paused.');
      }

      await debateSessionRepository.update(
        { id: debateSession.id },
        {
          status: DebateSessionStatus.Paused,
        },
      );

      const pausedEvent = await this.createDebateEvent(
        manager,
        debateSession,
        'debate.paused',
        this.bindActor(actor),
        {
          reason: this.optionalString(reason) ?? 'host_pause',
          currentTurnNumber: debateSession.currentTurnNumber,
        },
      );
      const touchedAgentIds = await this.collectSessionAgentIds(
        manager,
        debateSession.id,
      );

      return {
        debateSessionId: debateSession.id,
        threadId: debateSession.threadId,
        status: DebateSessionStatus.Paused,
        currentTurnNumber: debateSession.currentTurnNumber,
        eventId: pausedEvent.id,
        followUpEventIds: [] as string[],
        touchedAgentIds,
      };
    });

    await this.processEventIds([result.eventId]);
    await this.syncAgentStatuses(result.touchedAgentIds);

    return result;
  }

  async resumeDebate(actor: DebateActor, debateSessionId: string) {
    await this.moderationService.assertActorAllowed(actor);
    await this.sweepDebateSession(debateSessionId);

    const result = await this.dataSource.transaction(async (manager) => {
      const debateSessionRepository = manager.getRepository(DebateSessionEntity);
      const debateSession = await debateSessionRepository.findOneBy({
        id: debateSessionId,
      });

      if (!debateSession) {
        throw new NotFoundException(`Debate session ${debateSessionId} was not found.`);
      }

      this.assertHostActor(debateSession, actor);

      if (debateSession.status !== DebateSessionStatus.Paused) {
        throw new ConflictException('Only paused debates can be resumed.');
      }

      const seats = await this.loadSeats(manager, debateSession.id);
      const debateTurn = await this.ensurePendingTurn(
        manager,
        debateSession,
        seats,
        debateSession.currentTurnNumber,
      );
      const expectedSeat = seats.find((seat) => seat.id === debateTurn.seatId);

      if (!expectedSeat || expectedSeat.status !== DebateSeatStatus.Occupied || !expectedSeat.agentId) {
        throw new ConflictException(
          'A replacement debater must occupy the expected seat before resuming.',
        );
      }

      await debateSessionRepository.update(
        { id: debateSession.id },
        {
          status: DebateSessionStatus.Live,
          currentTurnNumber: debateTurn.turnNumber,
        },
      );

      const resumedEvent = await this.createDebateEvent(
        manager,
        debateSession,
        'debate.resumed',
        this.bindActor(actor),
        {
          currentTurnNumber: debateTurn.turnNumber,
        },
      );
      const assignedEvent = await this.createTurnAssignedEvent(
        manager,
        debateSession,
        debateTurn,
        seats,
      );

      return {
        debateSessionId: debateSession.id,
        threadId: debateSession.threadId,
        status: DebateSessionStatus.Live,
        currentTurnNumber: debateTurn.turnNumber,
        eventId: resumedEvent.id,
        followUpEventIds: [assignedEvent.id],
        touchedAgentIds: seats
          .map((seat) => seat.agentId)
          .filter((agentId): agentId is string => Boolean(agentId)),
      };
    });

    await this.processEventIds([result.eventId, ...result.followUpEventIds]);
    await this.syncAgentStatuses(result.touchedAgentIds);

    return result;
  }

  async endDebate(actor: DebateActor, debateSessionId: string) {
    await this.moderationService.assertActorAllowed(actor);
    await this.sweepDebateSession(debateSessionId);

    const result = await this.dataSource.transaction(async (manager) => {
      const debateSessionRepository = manager.getRepository(DebateSessionEntity);
      const debateTurnRepository = manager.getRepository(DebateTurnEntity);
      const debateSession = await debateSessionRepository.findOneBy({
        id: debateSessionId,
      });

      if (!debateSession) {
        throw new NotFoundException(`Debate session ${debateSessionId} was not found.`);
      }

      this.assertHostActor(debateSession, actor);

      if (
        debateSession.status !== DebateSessionStatus.Live &&
        debateSession.status !== DebateSessionStatus.Paused
      ) {
        throw new ConflictException('Only live or paused debates can be ended.');
      }

      const currentTurn = await debateTurnRepository.findOneBy({
        debateSessionId: debateSession.id,
        turnNumber: debateSession.currentTurnNumber,
      });

      if (currentTurn && currentTurn.status === DebateTurnStatus.Pending) {
        await debateTurnRepository.update(
          { id: currentTurn.id },
          {
            status: DebateTurnStatus.Skipped,
            deadlineAt: null,
            metadata: {
              ...currentTurn.metadata,
              endedAt: new Date().toISOString(),
            },
          },
        );
      }

      await debateSessionRepository.update(
        { id: debateSession.id },
        {
          status: DebateSessionStatus.Ended,
        },
      );

      const endedEvent = await this.createDebateEvent(
        manager,
        debateSession,
        'debate.ended',
        this.bindActor(actor),
        {
          finalTurnNumber: debateSession.currentTurnNumber,
        },
      );
      const touchedAgentIds = await this.collectSessionAgentIds(
        manager,
        debateSession.id,
      );

      return {
        debateSessionId: debateSession.id,
        threadId: debateSession.threadId,
        status: DebateSessionStatus.Ended,
        currentTurnNumber: debateSession.currentTurnNumber,
        eventId: endedEvent.id,
        followUpEventIds: [] as string[],
        touchedAgentIds,
      };
    });

    await this.processEventIds([result.eventId]);
    await this.syncAgentStatuses(result.touchedAgentIds);

    return result;
  }

  async assignReplacementSeat(actor: DebateActor, input: AssignReplacementInput) {
    await this.moderationService.assertActorAllowed(actor);

    const debateSessionId = this.requiredString(input.debateSessionId, 'debateSessionId');
    const agentId = this.requiredString(input.agentId, 'agentId');

    await this.moderationService.assertActorAllowed({
      type: SubjectType.Agent,
      id: agentId,
    });
    await this.sweepDebateSession(debateSessionId);

    const result = await this.dataSource.transaction(async (manager) => {
      const debateSessionRepository = manager.getRepository(DebateSessionEntity);
      const debateSeatRepository = manager.getRepository(DebateSeatEntity);
      const debateSession = await debateSessionRepository.findOneBy({
        id: debateSessionId,
      });

      if (!debateSession) {
        throw new NotFoundException(`Debate session ${debateSessionId} was not found.`);
      }

      this.assertHostActor(debateSession, actor);

      if (debateSession.status !== DebateSessionStatus.Paused) {
        throw new ConflictException('Replacement seating is only available while a debate is paused.');
      }

      if (!debateSession.freeEntry) {
        throw new ForbiddenException(
          'This debate does not allow replacement entry.',
        );
      }

      const seats = await this.loadSeats(manager, debateSession.id);
      const seat = this.resolveReplacingSeat(seats, input.seatId);

      const occupiedElsewhere = await debateSeatRepository
        .createQueryBuilder('seat')
        .innerJoin(
          DebateSessionEntity,
          'session',
          'session.id = seat.debate_session_id',
        )
        .where('seat.agent_id = :agentId', { agentId })
        .andWhere('seat.id != :seatId', { seatId: seat.id })
        .andWhere('session.status IN (:...statuses)', {
          statuses: [
            DebateSessionStatus.Pending,
            DebateSessionStatus.Live,
            DebateSessionStatus.Paused,
          ],
        })
        .getExists();

      if (occupiedElsewhere) {
        throw new ConflictException(
          'The replacement agent already occupies another active debate seat.',
        );
      }

      await debateSeatRepository.update(
        { id: seat.id },
        {
          agentId,
          status: DebateSeatStatus.Occupied,
        },
      );

      await this.ensureParticipant(
        manager,
        debateSession.threadId,
        {
          type: SubjectType.Agent,
          id: agentId,
        },
        ThreadParticipantRole.Member,
      );

      const replacementEvent = await this.createDebateEvent(
        manager,
        debateSession,
        'debate.seat.replaced',
        this.bindActor(actor),
        {
          seatId: seat.id,
          stance: seat.stance,
          replacementAgentId: agentId,
          currentTurnNumber: debateSession.currentTurnNumber,
        },
      );

      return {
        debateSessionId: debateSession.id,
        threadId: debateSession.threadId,
        seatId: seat.id,
        stance: seat.stance,
        status: DebateSeatStatus.Occupied,
        eventId: replacementEvent.id,
      };
    });

    await this.processEventIds([result.eventId]);

    return result;
  }

  async sweepDebateSession(debateSessionId: string): Promise<void> {
    const result = await this.dataSource.transaction(async (manager) => {
      const debateSessionRepository = manager.getRepository(DebateSessionEntity);
      const debateTurnRepository = manager.getRepository(DebateTurnEntity);
      const debateSeatRepository = manager.getRepository(DebateSeatEntity);
      const debateSession = await debateSessionRepository.findOneBy({
        id: debateSessionId,
      });

      if (!debateSession || debateSession.status !== DebateSessionStatus.Live) {
        return null;
      }

      const currentTurn = await debateTurnRepository.findOneBy({
        debateSessionId,
        turnNumber: debateSession.currentTurnNumber,
      });

      if (
        !currentTurn ||
        currentTurn.status !== DebateTurnStatus.Pending ||
        currentTurn.eventId ||
        !currentTurn.deadlineAt ||
        currentTurn.deadlineAt.getTime() > Date.now()
      ) {
        return null;
      }

      const seats = await this.loadSeats(manager, debateSession.id);
      const seat = seats.find((candidate) => candidate.id === currentTurn.seatId);

      if (!seat) {
        return null;
      }

      const touchedAgentIds = seats
        .map((candidate) => candidate.agentId)
        .filter((agentId): agentId is string => Boolean(agentId));

      await debateTurnRepository.update(
        { id: currentTurn.id },
        {
          status: DebateTurnStatus.Missed,
          metadata: {
            ...currentTurn.metadata,
            missedAt: new Date().toISOString(),
            missedSeatId: seat.id,
          },
        },
      );
      await debateSeatRepository.update(
        { id: seat.id },
        {
          agentId: null,
          status: DebateSeatStatus.Replacing,
        },
      );
      await debateSessionRepository.update(
        { id: debateSession.id },
        {
          status: DebateSessionStatus.Paused,
          currentTurnNumber: currentTurn.turnNumber + 1,
        },
      );

      const missedEvent = await this.createSystemDebateEvent(
        manager,
        debateSession,
        'debate.turn.missed',
        {
          seatId: seat.id,
          stance: seat.stance,
          missedAgentId: seat.agentId,
          turnNumber: currentTurn.turnNumber,
        },
      );
      const pausedEvent = await this.createSystemDebateEvent(
        manager,
        debateSession,
        'debate.paused',
        {
          reason: 'missed_turn',
          seatId: seat.id,
          stance: seat.stance,
          turnNumber: currentTurn.turnNumber,
        },
      );
      const replacementNeededEvent = await this.createSystemDebateEvent(
        manager,
        debateSession,
        'debate.seat.replacement_needed',
        {
          seatId: seat.id,
          stance: seat.stance,
          freeEntry: debateSession.freeEntry,
          missedTurnNumber: currentTurn.turnNumber,
        },
      );

      return {
        eventIds: [missedEvent.id, pausedEvent.id, replacementNeededEvent.id],
        touchedAgentIds,
      };
    });

    if (!result) {
      return;
    }

    await this.processEventIds(result.eventIds);
    await this.syncAgentStatuses(result.touchedAgentIds);
  }

  async prepareTurnSubmission(
    manager: EntityManager,
    actorAgentId: string,
    input: {
      debateSessionId: string;
      seatId?: string | null;
      turnNumber?: unknown;
    },
  ): Promise<PreparedTurnSubmission> {
    const debateSessionRepository = manager.getRepository(DebateSessionEntity);
    const debateTurnRepository = manager.getRepository(DebateTurnEntity);
    const debateSeatRepository = manager.getRepository(DebateSeatEntity);
    const debateSession = await debateSessionRepository.findOneBy({
      id: input.debateSessionId,
    });

    if (!debateSession) {
      throw new NotFoundException(
        `Debate session ${input.debateSessionId} was not found.`,
      );
    }

    if (debateSession.status !== DebateSessionStatus.Live) {
      throw new ConflictException('Debate turns can only be submitted while the debate is live.');
    }

    const expectedTurnNumber = debateSession.currentTurnNumber;
    const requestedTurnNumber = this.normalizeTurnNumber(
      input.turnNumber,
      expectedTurnNumber,
    );

    if (requestedTurnNumber !== expectedTurnNumber) {
      throw new ConflictException('Only the current debate turn may be submitted.');
    }

    const seat = await this.resolveSeatForTurnSubmission(
      debateSeatRepository,
      debateSession.id,
      actorAgentId,
      input.seatId,
    );

    if (seat.status !== DebateSeatStatus.Occupied || !seat.agentId) {
      throw new ConflictException('Only an occupied debate seat may submit a turn.');
    }

    let debateTurn = await debateTurnRepository.findOneBy({
      debateSessionId: debateSession.id,
      turnNumber: expectedTurnNumber,
    });

    if (!debateTurn) {
      const seats = await this.loadSeats(manager, debateSession.id);
      const existingTurnCount = await debateTurnRepository.countBy({
        debateSessionId: debateSession.id,
      });

      if (existingTurnCount === 0 && expectedTurnNumber === 1 && seats.length === 1) {
        debateTurn = await this.createPendingTurn(
          manager,
          debateSession,
          seat,
          expectedTurnNumber,
        );
      } else {
        debateTurn = await this.ensurePendingTurn(
          manager,
          debateSession,
          seats,
          expectedTurnNumber,
        );
      }
    }

    if (debateTurn.status !== DebateTurnStatus.Pending || debateTurn.eventId) {
      throw new ConflictException('The current debate turn is not accepting submissions.');
    }

    if (debateTurn.deadlineAt && debateTurn.deadlineAt.getTime() <= Date.now()) {
      throw new ConflictException('The current debate turn has already expired.');
    }

    if (debateTurn.seatId !== seat.id) {
      throw new ConflictException('It is not this seat\'s turn.');
    }

    return {
      debateSession,
      seat,
      debateTurn,
    };
  }

  async completeTurnSubmission(
    manager: EntityManager,
    input: {
      debateSession: DebateSessionEntity;
      debateTurn: DebateTurnEntity;
      seat: DebateSeatEntity;
      actorAgentId: string;
      eventId: string;
    },
  ) {
    const debateTurnRepository = manager.getRepository(DebateTurnEntity);
    const debateSessionRepository = manager.getRepository(DebateSessionEntity);
    const seats = await this.loadSeats(manager, input.debateSession.id);

    await debateTurnRepository.update(
      { id: input.debateTurn.id },
      {
        eventId: input.eventId,
        status: DebateTurnStatus.Completed,
        submittedAt: new Date(),
        metadata: {
          ...input.debateTurn.metadata,
          seatId: input.seat.id,
          submittedByAgentId: input.actorAgentId,
        },
      },
    );

    const nextTurnNumber = input.debateTurn.turnNumber + 1;

    if (seats.length < 2) {
      await debateSessionRepository.update(
        { id: input.debateSession.id },
        {
          currentTurnNumber: nextTurnNumber,
        },
      );

      return {
        followUpEventIds: [] as string[],
      };
    }

    const nextSeat = this.getOppositeSeat(seats, input.seat.id);

    if (nextSeat.status !== DebateSeatStatus.Occupied || !nextSeat.agentId) {
      await debateSessionRepository.update(
        { id: input.debateSession.id },
        {
          status: DebateSessionStatus.Paused,
          currentTurnNumber: nextTurnNumber,
        },
      );

      const replacementNeededEvent = await this.createSystemDebateEvent(
        manager,
        input.debateSession,
        'debate.seat.replacement_needed',
        {
          seatId: nextSeat.id,
          stance: nextSeat.stance,
          freeEntry: input.debateSession.freeEntry,
          missingTurnNumber: nextTurnNumber,
        },
      );
      const pausedEvent = await this.createSystemDebateEvent(
        manager,
        input.debateSession,
        'debate.paused',
        {
          reason: 'replacement_needed',
          seatId: nextSeat.id,
          stance: nextSeat.stance,
          turnNumber: nextTurnNumber,
        },
      );

      return {
        followUpEventIds: [replacementNeededEvent.id, pausedEvent.id],
      };
    }

    const nextTurn = await this.createPendingTurn(
      manager,
      input.debateSession,
      nextSeat,
      nextTurnNumber,
    );

    await debateSessionRepository.update(
      { id: input.debateSession.id },
      {
        currentTurnNumber: nextTurn.turnNumber,
      },
    );

    const assignedEvent = await this.createTurnAssignedEvent(
      manager,
      input.debateSession,
      nextTurn,
      seats,
    );

    return {
      followUpEventIds: [assignedEvent.id],
    };
  }

  async assertSpectatorCommentAllowed(actor: DebateActor, debateSessionId: string) {
    const debateSession = await this.debateSessionRepository.findOneBy({
      id: debateSessionId,
    });

    if (!debateSession) {
      throw new NotFoundException(`Debate session ${debateSessionId} was not found.`);
    }

    if (actor.type === SubjectType.Agent) {
      const occupiesSeat = await this.debateSeatRepository.exist({
        where: {
          debateSessionId,
          agentId: actor.id,
          status: DebateSeatStatus.Occupied,
        },
      });

      if (occupiesSeat) {
        throw new ForbiddenException(
          'Active debaters cannot post to the spectator feed.',
        );
      }
    }

    return debateSession;
  }

  private async createDebate(
    host: DebateActor,
    input: CreateDebateInput,
    humanHostAllowed: boolean,
  ) {
    const topic = this.requiredString(input.topic, 'topic');
    const proStance = this.requiredString(input.proStance, 'proStance');
    const conStance = this.requiredString(input.conStance, 'conStance');
    const proAgentId = this.requiredString(input.proAgentId, 'proAgentId');
    const conAgentId = this.requiredString(input.conAgentId, 'conAgentId');

    if (proAgentId === conAgentId) {
      throw new ConflictException('The pro and con seats must be assigned to different agents.');
    }

    await Promise.all([
      this.assertAgentEligible(proAgentId),
      this.assertAgentEligible(conAgentId),
    ]);

    const result = await this.dataSource.transaction(async (manager) => {
      const threadRepository = manager.getRepository(ThreadEntity);
      const debateSessionRepository = manager.getRepository(DebateSessionEntity);
      const debateSeatRepository = manager.getRepository(DebateSeatEntity);
      const thread = await threadRepository.save(
        threadRepository.create({
          contextType: ThreadContextType.DebateSpectator,
          visibility: ThreadVisibility.Public,
          title: topic,
        }),
      );
      const debateSession = await debateSessionRepository.save(
        debateSessionRepository.create({
          threadId: thread.id,
          topic,
          proStance,
          conStance,
          hostType: host.type,
          hostUserId: host.type === SubjectType.Human ? host.id : null,
          hostAgentId: host.type === SubjectType.Agent ? host.id : null,
          status: DebateSessionStatus.Pending,
          freeEntry: this.optionalBoolean(input.freeEntry) ?? false,
          humanHostAllowed,
          currentTurnNumber: 1,
        }),
      );
      const seats = await debateSeatRepository.save([
        debateSeatRepository.create({
          debateSessionId: debateSession.id,
          stance: DebateSeatStance.Pro,
          status: DebateSeatStatus.Occupied,
          agentId: proAgentId,
          seatOrder: 1,
        }),
        debateSeatRepository.create({
          debateSessionId: debateSession.id,
          stance: DebateSeatStance.Con,
          status: DebateSeatStatus.Occupied,
          agentId: conAgentId,
          seatOrder: 2,
        }),
      ]);

      await this.ensureParticipant(
        manager,
        thread.id,
        host,
        ThreadParticipantRole.Host,
      );
      await this.ensureParticipant(
        manager,
        thread.id,
        {
          type: SubjectType.Agent,
          id: proAgentId,
        },
        ThreadParticipantRole.Member,
      );
      await this.ensureParticipant(
        manager,
        thread.id,
        {
          type: SubjectType.Agent,
          id: conAgentId,
        },
        ThreadParticipantRole.Member,
      );

      const createdEvent = await this.createDebateEvent(
        manager,
        debateSession,
        'debate.create',
        this.bindActor(host),
        {
          topic,
          proStance,
          conStance,
          freeEntry: debateSession.freeEntry,
          humanHostAllowed: debateSession.humanHostAllowed,
          seats: seats.map((seat) => ({
            id: seat.id,
            stance: seat.stance,
            agentId: seat.agentId,
          })),
        },
      );

      const followUpEventIds: string[] = [];

      if (host.type === SubjectType.Agent) {
        const readyEvent = await this.createSystemDebateEvent(
          manager,
          debateSession,
          'debate.ready_to_start',
          {
            currentTurnNumber: debateSession.currentTurnNumber,
          },
        );
        followUpEventIds.push(readyEvent.id);
      }

      return {
        debateSessionId: debateSession.id,
        threadId: debateSession.threadId,
        status: debateSession.status,
        currentTurnNumber: debateSession.currentTurnNumber,
        eventId: createdEvent.id,
        followUpEventIds,
        seats: seats.map((seat) => this.serializeSeat(seat)),
      };
    });

    await this.processEventIds([result.eventId, ...result.followUpEventIds]);

    return result;
  }

  private async assertAgentEligible(agentId: string): Promise<void> {
    const agent = await this.agentRepository.findOneBy({ id: agentId });

    if (!agent) {
      throw new NotFoundException(`Agent ${agentId} was not found.`);
    }

    if (agent.status === AgentStatus.Suspended) {
      throw new ForbiddenException('Suspended agents cannot be seated in a debate.');
    }
  }

  private assertHostActor(
    debateSession: DebateSessionEntity,
    actor: DebateActor,
  ): void {
    const expectedHostId =
      debateSession.hostType === SubjectType.Human
        ? debateSession.hostUserId
        : debateSession.hostAgentId;

    if (debateSession.hostType !== actor.type || expectedHostId !== actor.id) {
      throw new ForbiddenException('Only the debate host can perform this action.');
    }
  }

  private async loadSeats(
    manager: EntityManager,
    debateSessionId: string,
  ): Promise<DebateSeatEntity[]> {
    return manager.getRepository(DebateSeatEntity).find({
      where: { debateSessionId },
      order: { seatOrder: 'ASC' },
    });
  }

  private async ensurePendingTurn(
    manager: EntityManager,
    debateSession: DebateSessionEntity,
    seats: DebateSeatEntity[],
    turnNumber: number,
  ): Promise<DebateTurnEntity> {
    const debateTurnRepository = manager.getRepository(DebateTurnEntity);
    const expectedSeat = await this.determineExpectedSeat(
      manager,
      debateSession.id,
      seats,
      turnNumber,
    );

    if (expectedSeat.status !== DebateSeatStatus.Occupied || !expectedSeat.agentId) {
      throw new ConflictException('The expected seat must be occupied before the turn can begin.');
    }

    const existingTurn = await debateTurnRepository.findOneBy({
      debateSessionId: debateSession.id,
      turnNumber,
    });

    if (!existingTurn) {
      return this.createPendingTurn(manager, debateSession, expectedSeat, turnNumber);
    }

    if (existingTurn.status !== DebateTurnStatus.Pending || existingTurn.eventId) {
      throw new ConflictException('The requested debate turn is already closed.');
    }

    await debateTurnRepository.update(
      { id: existingTurn.id },
      {
        seatId: expectedSeat.id,
        deadlineAt: this.buildTurnDeadline(),
        metadata: {
          ...existingTurn.metadata,
          stance: expectedSeat.stance,
          assignedAgentId: expectedSeat.agentId,
        },
      },
    );

    return debateTurnRepository.findOneByOrFail({ id: existingTurn.id });
  }

  private async createPendingTurn(
    manager: EntityManager,
    debateSession: DebateSessionEntity,
    seat: DebateSeatEntity,
    turnNumber: number,
  ): Promise<DebateTurnEntity> {
    if (seat.status !== DebateSeatStatus.Occupied || !seat.agentId) {
      throw new ConflictException('The expected seat must be occupied before the turn can begin.');
    }

    const debateTurnRepository = manager.getRepository(DebateTurnEntity);

    return debateTurnRepository.save(
      debateTurnRepository.create({
        debateSessionId: debateSession.id,
        seatId: seat.id,
        turnNumber,
        status: DebateTurnStatus.Pending,
        deadlineAt: this.buildTurnDeadline(),
        metadata: {
          stance: seat.stance,
          assignedAgentId: seat.agentId,
        },
      }),
    );
  }

  private async determineExpectedSeat(
    manager: EntityManager,
    debateSessionId: string,
    seats: DebateSeatEntity[],
    turnNumber: number,
  ): Promise<DebateSeatEntity> {
    if (seats.length !== 2) {
      throw new ConflictException('Debates must keep exactly two canonical seats.');
    }

    if (turnNumber <= 1) {
      const firstSeat = seats.find((seat) => seat.seatOrder === 1);

      if (!firstSeat) {
        throw new ConflictException('The opening debate seat could not be resolved.');
      }

      return firstSeat;
    }

    const previousTurn = await manager.getRepository(DebateTurnEntity).findOneBy({
      debateSessionId,
      turnNumber: turnNumber - 1,
    });

    if (!previousTurn) {
      return this.determineExpectedSeat(manager, debateSessionId, seats, 1);
    }

    const previousSeat = seats.find((seat) => seat.id === previousTurn.seatId);

    if (!previousSeat) {
      throw new ConflictException('The previous debate seat could not be resolved.');
    }

    if (previousTurn.status === DebateTurnStatus.Missed) {
      return previousSeat;
    }

    return this.getOppositeSeat(seats, previousSeat.id);
  }

  private getOppositeSeat(
    seats: DebateSeatEntity[],
    seatId: string,
  ): DebateSeatEntity {
    const oppositeSeat = seats.find((seat) => seat.id !== seatId);

    if (!oppositeSeat) {
      throw new ConflictException('A debate requires exactly two seats.');
    }

    return oppositeSeat;
  }

  private async resolveSeatForTurnSubmission(
    debateSeatRepository: Repository<DebateSeatEntity>,
    debateSessionId: string,
    actorAgentId: string,
    seatId?: string | null,
  ): Promise<DebateSeatEntity> {
    if (this.optionalString(seatId)) {
      const seat = await debateSeatRepository.findOneBy({
        id: seatId!,
        debateSessionId,
      });

      if (!seat) {
        throw new NotFoundException(`Debate seat ${seatId} was not found.`);
      }

      if (seat.agentId !== actorAgentId) {
        throw new ForbiddenException('Only the seated agent can submit this debate turn.');
      }

      return seat;
    }

    const seat = await debateSeatRepository.findOneBy({
      debateSessionId,
      agentId: actorAgentId,
    });

    if (!seat) {
      throw new ForbiddenException(
        'The agent does not occupy a debate seat for this session.',
      );
    }

    return seat;
  }

  private resolveReplacingSeat(
    seats: DebateSeatEntity[],
    requestedSeatId?: string | null,
  ): DebateSeatEntity {
    const requestedId = this.optionalString(requestedSeatId);

    if (requestedId) {
      const seat = seats.find((candidate) => candidate.id === requestedId);

      if (!seat) {
        throw new NotFoundException(`Debate seat ${requestedId} was not found.`);
      }

      if (seat.status !== DebateSeatStatus.Replacing || seat.agentId) {
        throw new ConflictException('Only a replacing debate seat can accept a replacement agent.');
      }

      return seat;
    }

    const replacingSeats = seats.filter(
      (seat) => seat.status === DebateSeatStatus.Replacing && !seat.agentId,
    );

    if (replacingSeats.length !== 1) {
      throw new BadRequestException('seatId is required when multiple seats are awaiting replacement.');
    }

    return replacingSeats[0];
  }

  private async createDebateEvent(
    manager: EntityManager,
    debateSession: DebateSessionEntity,
    eventType: string,
    actor: Pick<EventEntity, 'actorType' | 'actorUserId' | 'actorAgentId'>,
    metadata: Record<string, unknown>,
  ) {
    return manager.getRepository(EventEntity).save(
      manager.getRepository(EventEntity).create({
        threadId: debateSession.threadId,
        eventType,
        ...actor,
        targetType: 'debate_session',
        targetId: debateSession.id,
        contentType: EventContentType.None,
        content: null,
        metadata,
      }),
    );
  }

  private createSystemDebateEvent(
    manager: EntityManager,
    debateSession: DebateSessionEntity,
    eventType: string,
    metadata: Record<string, unknown>,
  ) {
    return this.createDebateEvent(
      manager,
      debateSession,
      eventType,
      this.bindSystemActor(),
      metadata,
    );
  }

  private async createTurnAssignedEvent(
    manager: EntityManager,
    debateSession: DebateSessionEntity,
    debateTurn: DebateTurnEntity,
    seats: DebateSeatEntity[],
  ) {
    const seat = seats.find((candidate) => candidate.id === debateTurn.seatId);

    if (!seat) {
      throw new ConflictException('The assigned debate seat could not be resolved.');
    }

    return this.createSystemDebateEvent(manager, debateSession, 'debate.turn.assigned', {
      seatId: seat.id,
      stance: seat.stance,
      agentId: seat.agentId,
      turnNumber: debateTurn.turnNumber,
      deadlineAt: debateTurn.deadlineAt?.toISOString() ?? null,
    });
  }

  private async collectSessionAgentIds(
    manager: EntityManager,
    debateSessionId: string,
  ): Promise<string[]> {
    const seats = await this.loadSeats(manager, debateSessionId);

    return seats
      .map((seat) => seat.agentId)
      .filter((agentId): agentId is string => Boolean(agentId));
  }

  private async ensureParticipant(
    manager: EntityManager,
    threadId: string,
    actor: DebateActor,
    role: ThreadParticipantRole,
  ): Promise<void> {
    const participantRepository = manager.getRepository(ThreadParticipantEntity);
    const existingParticipant = await participantRepository.findOneBy({
      threadId,
      participantType: actor.type,
      participantSubjectId: actor.id,
    });

    if (existingParticipant) {
      const nextRole = this.mergeParticipantRole(existingParticipant.role, role);

      if (nextRole !== existingParticipant.role) {
        await participantRepository.update(
          { id: existingParticipant.id },
          { role: nextRole },
        );
      }

      return;
    }

    await participantRepository.save(
      participantRepository.create({
        threadId,
        participantType: actor.type,
        participantSubjectId: actor.id,
        userId: actor.type === SubjectType.Human ? actor.id : null,
        agentId: actor.type === SubjectType.Agent ? actor.id : null,
        role,
      }),
    );
  }

  private async processEventIds(eventIds: string[]): Promise<void> {
    for (const eventId of eventIds) {
      await this.notificationsService.processEventById(eventId);
    }
  }

  private async syncAgentStatuses(agentIds: string[]): Promise<void> {
    const uniqueAgentIds = [...new Set(agentIds.filter(Boolean))];

    for (const agentId of uniqueAgentIds) {
      const agent = await this.agentRepository.findOneBy({ id: agentId });

      if (!agent || agent.status === AgentStatus.Suspended) {
        continue;
      }

      const hasLiveSeat = await this.debateSeatRepository
        .createQueryBuilder('seat')
        .innerJoin(
          DebateSessionEntity,
          'session',
          'session.id = seat.debate_session_id',
        )
        .where('seat.agent_id = :agentId', { agentId })
        .andWhere('seat.status = :seatStatus', {
          seatStatus: DebateSeatStatus.Occupied,
        })
        .andWhere('session.status = :sessionStatus', {
          sessionStatus: DebateSessionStatus.Live,
        })
        .getExists();

      const nextStatus = hasLiveSeat ? AgentStatus.Debating : AgentStatus.Online;

      if (agent.status !== nextStatus) {
        await this.agentRepository.update({ id: agentId }, { status: nextStatus });
      }
    }
  }

  private bindActor(actor: DebateActor) {
    if (actor.type === SubjectType.Human) {
      return {
        actorType: EventActorType.Human,
        actorUserId: actor.id,
        actorAgentId: null,
      };
    }

    return {
      actorType: EventActorType.Agent,
      actorUserId: null,
      actorAgentId: actor.id,
    };
  }

  private bindSystemActor() {
    return {
      actorType: EventActorType.System,
      actorUserId: null,
      actorAgentId: null,
    };
  }

  private mergeParticipantRole(
    currentRole: ThreadParticipantRole,
    requestedRole: ThreadParticipantRole,
  ): ThreadParticipantRole {
    const priorities: Record<ThreadParticipantRole, number> = {
      [ThreadParticipantRole.Member]: 1,
      [ThreadParticipantRole.Spectator]: 2,
      [ThreadParticipantRole.Host]: 3,
    };

    return priorities[currentRole] >= priorities[requestedRole]
      ? currentRole
      : requestedRole;
  }

  private buildTurnDeadline() {
    return new Date(Date.now() + this.defaultTurnDeadlineMs);
  }

  private normalizeTurnNumber(value: unknown, fallback: number): number {
    if (value === undefined || value === null || value === '') {
      return fallback;
    }

    const parsed = typeof value === 'number' ? value : Number.parseInt(String(value), 10);

    if (!Number.isInteger(parsed) || parsed <= 0) {
      throw new BadRequestException('turnNumber must be a positive integer.');
    }

    return parsed;
  }

  private requiredString(value: unknown, fieldName: string): string {
    const normalized = this.optionalString(value);

    if (!normalized) {
      throw new BadRequestException(`${fieldName} is required.`);
    }

    return normalized;
  }

  private optionalString(value: unknown): string | undefined {
    if (typeof value !== 'string') {
      return undefined;
    }

    const normalized = value.trim();
    return normalized || undefined;
  }

  private optionalBoolean(value: unknown): boolean | undefined {
    return typeof value === 'boolean' ? value : undefined;
  }

  private serializeHost(debateSession: DebateSessionEntity) {
    return {
      type: debateSession.hostType,
      id:
        debateSession.hostType === SubjectType.Human
          ? debateSession.hostUserId
          : debateSession.hostAgentId,
    };
  }

  private serializeSeat(seat: DebateSeatEntity) {
    return {
      id: seat.id,
      stance: seat.stance,
      status: seat.status,
      agentId: seat.agentId,
      seatOrder: seat.seatOrder,
    };
  }

  private serializeTurn(turn: DebateTurnEntity, seats: DebateSeatEntity[]) {
    const seat = seats.find((candidate) => candidate.id === turn.seatId);

    return {
      id: turn.id,
      seatId: turn.seatId,
      stance: seat?.stance ?? null,
      turnNumber: turn.turnNumber,
      status: turn.status,
      eventId: turn.eventId,
      deadlineAt: turn.deadlineAt?.toISOString() ?? null,
      submittedAt: turn.submittedAt?.toISOString() ?? null,
      metadata: turn.metadata,
      event: turn.event ? this.serializeEvent(turn.event) : null,
    };
  }

  private serializeEvent(event: EventEntity) {
    return {
      id: event.id,
      type: event.eventType,
      actorType: event.actorType,
      actorUserId: event.actorUserId,
      actorAgentId: event.actorAgentId,
      targetType: event.targetType,
      targetId: event.targetId,
      contentType: event.contentType,
      content: event.content,
      metadata: event.metadata,
      occurredAt: event.occurredAt.toISOString(),
    };
  }
}
