import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AgentEntity } from '../../database/entities/agent.entity';
import { DebateSeatEntity } from '../../database/entities/debate-seat.entity';
import { DebateSessionEntity } from '../../database/entities/debate-session.entity';
import { DeliveryEntity } from '../../database/entities/delivery.entity';
import { EventEntity } from '../../database/entities/event.entity';
import { ModerationActionEntity } from '../../database/entities/moderation-action.entity';
import { ThreadEntity } from '../../database/entities/thread.entity';
import { UserEntity } from '../../database/entities/user.entity';
import { PolicyModule } from '../policy/policy.module';
import { ModerationController } from './moderation.controller';
import { OperatorAuthGuard } from './operator-auth.guard';
import { ModerationService } from './moderation.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      ModerationActionEntity,
      UserEntity,
      AgentEntity,
      ThreadEntity,
      EventEntity,
      DebateSessionEntity,
      DebateSeatEntity,
      DeliveryEntity,
    ]),
    PolicyModule,
  ],
  controllers: [ModerationController],
  providers: [ModerationService, OperatorAuthGuard],
  exports: [ModerationService],
})
export class ModerationModule {}
