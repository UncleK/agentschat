import { Column, Entity, Index, JoinColumn, ManyToOne } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { DebateTurnStatus } from '../domain.enums';
import { DebateSeatEntity } from './debate-seat.entity';
import { DebateSessionEntity } from './debate-session.entity';
import { EventEntity } from './event.entity';

@Entity({ name: 'debate_turns' })
@Index(
  'IDX_debate_turns_session_turn_number_unique',
  ['debateSessionId', 'turnNumber'],
  {
    unique: true,
  },
)
@Index('IDX_debate_turns_event_id_unique', ['eventId'], { unique: true })
export class DebateTurnEntity extends BaseTableEntity {
  @Column({ name: 'debate_session_id', type: 'uuid' })
  debateSessionId!: string;

  @ManyToOne(
    () => DebateSessionEntity,
    (debateSession) => debateSession.turns,
    {
      onDelete: 'CASCADE',
    },
  )
  @JoinColumn({ name: 'debate_session_id' })
  debateSession!: DebateSessionEntity;

  @Column({ name: 'seat_id', type: 'uuid' })
  seatId!: string;

  @ManyToOne(() => DebateSeatEntity, (seat) => seat.turns, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'seat_id' })
  seat!: DebateSeatEntity;

  @Column({ name: 'turn_number', type: 'integer' })
  turnNumber!: number;

  @Column({
    type: 'enum',
    enum: DebateTurnStatus,
    enumName: 'debate_turn_status_enum',
    default: DebateTurnStatus.Pending,
  })
  status = DebateTurnStatus.Pending;

  @Column({ name: 'event_id', type: 'uuid', nullable: true })
  eventId: string | null = null;

  @ManyToOne(() => EventEntity, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'event_id' })
  event: EventEntity | null = null;

  @Column({ name: 'deadline_at', type: 'timestamptz', nullable: true })
  deadlineAt: Date | null = null;

  @Column({ name: 'submitted_at', type: 'timestamptz', nullable: true })
  submittedAt: Date | null = null;

  @Column({ name: 'metadata', type: 'jsonb', default: () => "'{}'::jsonb" })
  metadata: Record<string, unknown> = {};
}
