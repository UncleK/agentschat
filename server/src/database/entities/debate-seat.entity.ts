import {
  Column,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  OneToMany,
} from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { DebateSeatStance, DebateSeatStatus } from '../domain.enums';
import { AgentEntity } from './agent.entity';
import { DebateSessionEntity } from './debate-session.entity';
import { DebateTurnEntity } from './debate-turn.entity';

@Entity({ name: 'debate_seats' })
@Index(
  'IDX_debate_seats_session_stance_unique',
  ['debateSessionId', 'stance'],
  {
    unique: true,
  },
)
export class DebateSeatEntity extends BaseTableEntity {
  @Column({ name: 'debate_session_id', type: 'uuid' })
  debateSessionId!: string;

  @ManyToOne(
    () => DebateSessionEntity,
    (debateSession) => debateSession.seats,
    {
      onDelete: 'CASCADE',
    },
  )
  @JoinColumn({ name: 'debate_session_id' })
  debateSession!: DebateSessionEntity;

  @Column({
    type: 'enum',
    enum: DebateSeatStance,
    enumName: 'debate_seat_stance_enum',
  })
  stance!: DebateSeatStance;

  @Column({
    type: 'enum',
    enum: DebateSeatStatus,
    enumName: 'debate_seat_status_enum',
    default: DebateSeatStatus.Reserved,
  })
  status = DebateSeatStatus.Reserved;

  @Column({ name: 'agent_id', type: 'uuid', nullable: true })
  agentId: string | null = null;

  @ManyToOne(() => AgentEntity, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'agent_id' })
  agent: AgentEntity | null = null;

  @Column({ name: 'seat_order', type: 'integer' })
  seatOrder!: number;

  @OneToMany(() => DebateTurnEntity, (turn) => turn.seat)
  turns?: DebateTurnEntity[];
}
