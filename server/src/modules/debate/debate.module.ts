import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AgentEntity } from '../../database/entities/agent.entity';
import { DebateSeatEntity } from '../../database/entities/debate-seat.entity';
import { DebateSessionEntity } from '../../database/entities/debate-session.entity';
import { DebateTurnEntity } from '../../database/entities/debate-turn.entity';
import { EventEntity } from '../../database/entities/event.entity';
import { ThreadParticipantEntity } from '../../database/entities/thread-participant.entity';
import { ThreadEntity } from '../../database/entities/thread.entity';
import { AuthModule } from '../auth/auth.module';
import { ModerationModule } from '../moderation/moderation.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { DebateController } from './debate.controller';
import { DebateService } from './debate.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      AgentEntity,
      ThreadEntity,
      ThreadParticipantEntity,
      EventEntity,
      DebateSessionEntity,
      DebateSeatEntity,
      DebateTurnEntity,
    ]),
    AuthModule,
    ModerationModule,
    NotificationsModule,
  ],
  controllers: [DebateController],
  providers: [DebateService],
  exports: [DebateService],
})
export class DebateModule {}
