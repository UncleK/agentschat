import { Module, forwardRef } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AgentConnectionEntity } from '../../database/entities/agent-connection.entity';
import { AgentEntity } from '../../database/entities/agent.entity';
import { AssetEntity } from '../../database/entities/asset.entity';
import { DebateSeatEntity } from '../../database/entities/debate-seat.entity';
import { DebateSessionEntity } from '../../database/entities/debate-session.entity';
import { DebateTurnEntity } from '../../database/entities/debate-turn.entity';
import { EventEntity } from '../../database/entities/event.entity';
import { FollowEntity } from '../../database/entities/follow.entity';
import { ForumTopicViewEntity } from '../../database/entities/forum-topic-view.entity';
import { ThreadParticipantEntity } from '../../database/entities/thread-participant.entity';
import { ThreadEntity } from '../../database/entities/thread.entity';
import { AssetsModule } from '../assets/assets.module';
import { AuthModule } from '../auth/auth.module';
import { DebateModule } from '../debate/debate.module';
import { FederationAuthGuard } from '../federation/federation-auth.guard';
import { FederationCredentialsService } from '../federation/federation-credentials.service';
import { ModerationModule } from '../moderation/moderation.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { PolicyModule } from '../policy/policy.module';
import { ContentController } from './content.controller';
import { ContentService } from './content.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      AgentConnectionEntity,
      AgentEntity,
      AssetEntity,
      ThreadEntity,
      ThreadParticipantEntity,
      EventEntity,
      FollowEntity,
      ForumTopicViewEntity,
      DebateSessionEntity,
      DebateSeatEntity,
      DebateTurnEntity,
    ]),
    AssetsModule,
    AuthModule,
    PolicyModule,
    forwardRef(() => DebateModule),
    NotificationsModule,
    ModerationModule,
  ],
  controllers: [ContentController],
  providers: [
    ContentService,
    FederationCredentialsService,
    FederationAuthGuard,
  ],
  exports: [ContentService],
})
export class ContentModule {}
