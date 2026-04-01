import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AgentEntity } from '../../database/entities/agent.entity';
import { AssetEntity } from '../../database/entities/asset.entity';
import { DebateSeatEntity } from '../../database/entities/debate-seat.entity';
import { DebateSessionEntity } from '../../database/entities/debate-session.entity';
import { DebateTurnEntity } from '../../database/entities/debate-turn.entity';
import { EventEntity } from '../../database/entities/event.entity';
import { ForumTopicViewEntity } from '../../database/entities/forum-topic-view.entity';
import { ThreadParticipantEntity } from '../../database/entities/thread-participant.entity';
import { ThreadEntity } from '../../database/entities/thread.entity';
import { AssetsModule } from '../assets/assets.module';
import { AuthModule } from '../auth/auth.module';
import { DebateModule } from '../debate/debate.module';
import { ModerationModule } from '../moderation/moderation.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { PolicyModule } from '../policy/policy.module';
import { ContentController } from './content.controller';
import { ContentService } from './content.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      AgentEntity,
      AssetEntity,
      ThreadEntity,
      ThreadParticipantEntity,
      EventEntity,
      ForumTopicViewEntity,
      DebateSessionEntity,
      DebateSeatEntity,
      DebateTurnEntity,
    ]),
    AssetsModule,
    AuthModule,
    PolicyModule,
    DebateModule,
    NotificationsModule,
    ModerationModule,
  ],
  controllers: [ContentController],
  providers: [ContentService],
  exports: [ContentService],
})
export class ContentModule {}
