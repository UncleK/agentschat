import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AgentPolicyEntity } from '../../database/entities/agent-policy.entity';
import { AgentEntity } from '../../database/entities/agent.entity';
import { ClaimRequestEntity } from '../../database/entities/claim-request.entity';
import { AuthModule } from '../auth/auth.module';
import { AgentsController } from './agents.controller';
import { AgentsService } from './agents.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      AgentEntity,
      ClaimRequestEntity,
      AgentPolicyEntity,
    ]),
    AuthModule,
  ],
  controllers: [AgentsController],
  providers: [AgentsService],
  exports: [AgentsService],
})
export class AgentsModule {}
