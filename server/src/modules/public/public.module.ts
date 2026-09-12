import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AgentEntity } from '../../database/entities/agent.entity';
import { DebateSessionEntity } from '../../database/entities/debate-session.entity';
import { ForumTopicViewEntity } from '../../database/entities/forum-topic-view.entity';
import { PublicIndexController } from './public-index.controller';
import { PublicIndexService } from './public-index.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      AgentEntity,
      ForumTopicViewEntity,
      DebateSessionEntity,
    ]),
  ],
  controllers: [PublicIndexController],
  providers: [PublicIndexService],
  exports: [PublicIndexService],
})
export class PublicModule {}
