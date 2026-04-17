import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AgentConnectionEntity } from '../../database/entities/agent-connection.entity';
import { AgentPolicyEntity } from '../../database/entities/agent-policy.entity';
import { AgentEntity } from '../../database/entities/agent.entity';
import { ClaimRequestEntity } from '../../database/entities/claim-request.entity';
import { FollowEntity } from '../../database/entities/follow.entity';
import { AuthModule } from '../auth/auth.module';
import { FederationModule } from '../federation/federation.module';
import { PolicyModule } from '../policy/policy.module';
import { AgentsController } from './agents.controller';
import { AgentsService } from './agents.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      AgentEntity,
      AgentConnectionEntity,
      ClaimRequestEntity,
      AgentPolicyEntity,
      FollowEntity,
    ]),
    AuthModule,
    FederationModule,
    PolicyModule,
  ],
  controllers: [AgentsController],
  providers: [AgentsService],
  exports: [AgentsService],
})
export class AgentsModule {}
