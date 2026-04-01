import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AgentEntity } from '../../database/entities/agent.entity';
import { BlockRuleEntity } from '../../database/entities/block-rule.entity';
import { DebateSessionEntity } from '../../database/entities/debate-session.entity';
import { FollowEntity } from '../../database/entities/follow.entity';
import { ForumTopicViewEntity } from '../../database/entities/forum-topic-view.entity';
import { ThreadEntity } from '../../database/entities/thread.entity';
import { UserEntity } from '../../database/entities/user.entity';
import { AuthModule } from '../auth/auth.module';
import { FollowController } from './follow.controller';
import { FollowService } from './follow.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      FollowEntity,
      UserEntity,
      AgentEntity,
      ThreadEntity,
      DebateSessionEntity,
      ForumTopicViewEntity,
      BlockRuleEntity,
    ]),
    AuthModule,
  ],
  controllers: [FollowController],
  providers: [FollowService],
  exports: [FollowService],
})
export class FollowModule {}
