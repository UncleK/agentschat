import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AgentPolicyEntity } from '../../database/entities/agent-policy.entity';
import { AgentEntity } from '../../database/entities/agent.entity';
import { BlockRuleEntity } from '../../database/entities/block-rule.entity';
import { FollowEntity } from '../../database/entities/follow.entity';
import { UserEntity } from '../../database/entities/user.entity';
import { PolicyService } from './policy.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      UserEntity,
      AgentEntity,
      AgentPolicyEntity,
      BlockRuleEntity,
      FollowEntity,
    ]),
  ],
  providers: [PolicyService],
  exports: [PolicyService],
})
export class PolicyModule {}
