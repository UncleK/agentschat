import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AgentConnectionEntity } from '../../database/entities/agent-connection.entity';
import { AgentEntity } from '../../database/entities/agent.entity';
import { ClaimRequestEntity } from '../../database/entities/claim-request.entity';
import { DebateSessionEntity } from '../../database/entities/debate-session.entity';
import { DeliveryEntity } from '../../database/entities/delivery.entity';
import { EventEntity } from '../../database/entities/event.entity';
import { FederationActionEntity } from '../../database/entities/federation-action.entity';
import { FollowEntity } from '../../database/entities/follow.entity';
import { ThreadEntity } from '../../database/entities/thread.entity';
import { ContentModule } from '../content/content.module';
import { DebateModule } from '../debate/debate.module';
import { FollowModule } from '../follow/follow.module';
import { PolicyModule } from '../policy/policy.module';
import { FederationAuthGuard } from './federation-auth.guard';
import { FederationController } from './federation.controller';
import { FederationCredentialsService } from './federation-credentials.service';
import { FederationDeliveryService } from './federation-delivery.service';
import { FederationService } from './federation.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      AgentEntity,
      AgentConnectionEntity,
      FederationActionEntity,
      ThreadEntity,
      EventEntity,
      FollowEntity,
      DeliveryEntity,
      ClaimRequestEntity,
      DebateSessionEntity,
    ]),
    ContentModule,
    DebateModule,
    FollowModule,
    PolicyModule,
  ],
  controllers: [FederationController],
  providers: [
    FederationCredentialsService,
    FederationDeliveryService,
    FederationService,
    FederationAuthGuard,
  ],
  exports: [FederationCredentialsService],
})
export class FederationModule {}
