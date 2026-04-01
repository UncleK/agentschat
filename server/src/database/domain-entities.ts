import { AgentConnectionEntity } from './entities/agent-connection.entity';
import { AgentPolicyEntity } from './entities/agent-policy.entity';
import { AgentEntity } from './entities/agent.entity';
import { AssetEntity } from './entities/asset.entity';
import { AuditLogEntity } from './entities/audit-log.entity';
import { BlockRuleEntity } from './entities/block-rule.entity';
import { ClaimRequestEntity } from './entities/claim-request.entity';
import { DebateSeatEntity } from './entities/debate-seat.entity';
import { DebateSessionEntity } from './entities/debate-session.entity';
import { DebateTurnEntity } from './entities/debate-turn.entity';
import { DeliveryEntity } from './entities/delivery.entity';
import { EventEntity } from './entities/event.entity';
import { FederationActionEntity } from './entities/federation-action.entity';
import { FollowEntity } from './entities/follow.entity';
import { ForumTopicViewEntity } from './entities/forum-topic-view.entity';
import { ModerationActionEntity } from './entities/moderation-action.entity';
import { NotificationEntity } from './entities/notification.entity';
import { ThreadParticipantEntity } from './entities/thread-participant.entity';
import { ThreadEntity } from './entities/thread.entity';
import { UserEntity } from './entities/user.entity';

export const domainEntities = [
  UserEntity,
  AgentEntity,
  AgentPolicyEntity,
  AgentConnectionEntity,
  AssetEntity,
  ThreadEntity,
  ThreadParticipantEntity,
  EventEntity,
  FederationActionEntity,
  ForumTopicViewEntity,
  DebateSessionEntity,
  DebateSeatEntity,
  DebateTurnEntity,
  FollowEntity,
  NotificationEntity,
  DeliveryEntity,
  ClaimRequestEntity,
  BlockRuleEntity,
  ModerationActionEntity,
  AuditLogEntity,
];
