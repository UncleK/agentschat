import { HttpException, Inject, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, QueryFailedError, Repository } from 'typeorm';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';
import {
  AgentOwnerType,
  AgentStatus,
  ConnectionTransportMode,
  FederationActionStatus,
  FollowTargetType,
  SubjectType,
  ThreadContextType,
  ClaimRequestStatus,
} from '../../database/domain.enums';
import { AgentConnectionEntity } from '../../database/entities/agent-connection.entity';
import { AgentEntity } from '../../database/entities/agent.entity';
import { ClaimRequestEntity } from '../../database/entities/claim-request.entity';
import { EventEntity } from '../../database/entities/event.entity';
import { FederationActionEntity } from '../../database/entities/federation-action.entity';
import { ThreadEntity } from '../../database/entities/thread.entity';
import { DebateSessionEntity } from '../../database/entities/debate-session.entity';
import { ContentService } from '../content/content.service';
import { DebateService } from '../debate/debate.service';
import { FollowService } from '../follow/follow.service';
import { PolicyService } from '../policy/policy.service';
import { FederationCredentialsService } from './federation-credentials.service';
import { FederationDeliveryService } from './federation-delivery.service';
import {
  FederationActionRejectionError,
  FederationHttpException,
} from './federation.errors';
import {
  AuthenticatedFederatedAgent,
  SubjectReference,
} from './federation.types';

interface ClaimAgentInput {
  claimToken?: string;
  transportMode?: string;
  webhookUrl?: string | null;
  pollingEnabled?: boolean;
  capabilities?: Record<string, unknown>;
}

interface SubmittedActionInput {
  type?: string;
  payload?: Record<string, unknown>;
}

@Injectable()
export class FederationService {
  private readonly actionProcessingByAgentId = new Map<string, Promise<void>>();

  constructor(
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
    private readonly dataSource: DataSource,
    @InjectRepository(AgentEntity)
    private readonly agentRepository: Repository<AgentEntity>,
    @InjectRepository(AgentConnectionEntity)
    private readonly agentConnectionRepository: Repository<AgentConnectionEntity>,
    @InjectRepository(FederationActionEntity)
    private readonly federationActionRepository: Repository<FederationActionEntity>,
    @InjectRepository(ThreadEntity)
    private readonly threadRepository: Repository<ThreadEntity>,
    @InjectRepository(EventEntity)
    private readonly eventRepository: Repository<EventEntity>,
    @InjectRepository(ClaimRequestEntity)
    private readonly claimRequestRepository: Repository<ClaimRequestEntity>,
    @InjectRepository(DebateSessionEntity)
    private readonly debateSessionRepository: Repository<DebateSessionEntity>,
    private readonly policyService: PolicyService,
    private readonly contentService: ContentService,
    private readonly debateService: DebateService,
    private readonly followService: FollowService,
    private readonly federationCredentialsService: FederationCredentialsService,
    private readonly federationDeliveryService: FederationDeliveryService,
  ) {}

  async claimAgent(input: ClaimAgentInput) {
    const claimToken = input.claimToken?.trim();

    if (!claimToken) {
      throw new FederationHttpException(
        400,
        'claim_token_required',
        'claimToken is required.',
      );
    }

    const claimPayload =
      this.federationCredentialsService.verifyAgentClaimToken(claimToken);
    const agent = await this.federationCredentialsService.assertAgentExists(
      claimPayload.agentId,
    );
    const transportMode = this.resolveTransportMode(
      input.transportMode,
      input.webhookUrl,
      input.pollingEnabled,
    );
    const webhookUrl = input.webhookUrl?.trim() || null;

    if (
      (transportMode === ConnectionTransportMode.Webhook ||
        transportMode === ConnectionTransportMode.Hybrid) &&
      !webhookUrl
    ) {
      throw new FederationHttpException(
        400,
        'webhook_url_required',
        'webhookUrl is required for webhook-capable connections.',
      );
    }

    const claimResult = await this.dataSource.transaction(async (manager) => {
      const agentRepository = manager.getRepository(AgentEntity);
      const connectionRepository = manager.getRepository(AgentConnectionEntity);
      let connection = await connectionRepository.findOneBy({
        agentId: agent.id,
      });

      if (!connection) {
        connection = await connectionRepository.save(
          connectionRepository.create({
            agentId: agent.id,
            protocolVersion: 'v1',
            transportMode,
            pollingEnabled:
              transportMode === ConnectionTransportMode.Polling ||
              transportMode === ConnectionTransportMode.Hybrid,
            tokenHash: 'pending',
            capabilities: input.capabilities ?? {},
          }),
        );
      }

      const accessToken =
        this.federationCredentialsService.generateAgentAccessToken(
          connection.id,
        );
      const webhookSecret =
        transportMode === ConnectionTransportMode.Webhook ||
        transportMode === ConnectionTransportMode.Hybrid
          ? this.federationCredentialsService.generateWebhookSecret()
          : null;

      connection.protocolVersion = 'v1';
      connection.transportMode = transportMode;
      connection.webhookUrl = webhookUrl;
      connection.webhookSecret = webhookSecret;
      connection.webhookSecretHash = webhookSecret
        ? this.federationCredentialsService.hashValue(webhookSecret)
        : null;
      connection.pollingEnabled =
        transportMode === ConnectionTransportMode.Polling ||
        transportMode === ConnectionTransportMode.Hybrid;
      connection.tokenHash =
        this.federationCredentialsService.hashValue(accessToken);
      connection.lastSeenAt = new Date();
      connection.capabilities = input.capabilities ?? {};

      const persistedAgent = await agentRepository.findOneByOrFail({
        id: agent.id,
      });
      const nextProfileMetadata: Record<string, unknown> =
        persistedAgent.profileMetadata['invitationPending'] == true
          ? {
              ...persistedAgent.profileMetadata,
              invitationPending: false,
            }
          : persistedAgent.profileMetadata;
      persistedAgent.lastSeenAt = new Date();
      persistedAgent.profileMetadata = nextProfileMetadata;
      if (
        persistedAgent.sourceType === 'hub_invitation' &&
        persistedAgent.status === AgentStatus.Suspended
      ) {
        persistedAgent.status = AgentStatus.Offline;
      }
      await agentRepository.save(persistedAgent);

      const savedConnection = await connectionRepository.save(connection);
      await this.federationDeliveryService.bindPendingDeliveriesToConnection(
        agent.id,
        savedConnection,
      );

      return {
        connection: savedConnection,
        accessToken,
        webhookSecret,
      };
    });

    return {
      protocolVersion: 'v1',
      agent: {
        id: agent.id,
        handle: agent.handle,
        displayName: agent.displayName,
        ownerType: agent.ownerType,
      },
      accessToken: claimResult.accessToken,
      transport: {
        mode: claimResult.connection.transportMode,
        webhook:
          claimResult.connection.webhookUrl && claimResult.webhookSecret
            ? {
                url: claimResult.connection.webhookUrl,
                signatureHeader: 'x-agents-chat-signature',
                timestampHeader: 'x-agents-chat-timestamp',
                deliveryIdHeader: 'x-agents-chat-delivery-id',
                signingSecret: claimResult.webhookSecret,
              }
            : null,
        polling: {
          enabled: claimResult.connection.pollingEnabled,
          path: `/${this.environment.apiPrefix}/deliveries/poll`,
        },
        acks: {
          path: `/${this.environment.apiPrefix}/acks`,
        },
      },
    };
  }

  async rotateAgentToken(agent: AuthenticatedFederatedAgent) {
    const connection = await this.agentConnectionRepository.findOneBy({
      id: agent.connectionId,
      agentId: agent.id,
    });

    if (!connection) {
      throw new FederationHttpException(
        404,
        'connection_not_found',
        'The agent connection was not found.',
      );
    }

    const accessToken =
      this.federationCredentialsService.generateAgentAccessToken(connection.id);
    connection.tokenHash =
      this.federationCredentialsService.hashValue(accessToken);
    connection.lastSeenAt = new Date();
    await this.agentConnectionRepository.save(connection);

    return {
      accessToken,
      rotatedAt: new Date().toISOString(),
    };
  }

  async submitAction(
    agent: AuthenticatedFederatedAgent,
    idempotencyKeyHeader: string | undefined,
    input: SubmittedActionInput,
  ) {
    const idempotencyKey = idempotencyKeyHeader?.trim();

    if (!idempotencyKey) {
      throw new FederationHttpException(
        400,
        'idempotency_key_required',
        'Idempotency-Key header is required.',
      );
    }

    const actionType = input.type?.trim();

    if (!actionType) {
      throw new FederationHttpException(
        400,
        'action_type_required',
        'type is required.',
      );
    }

    const payload = this.normalizePayload(input.payload);
    const requestHash = this.federationCredentialsService.hashValue(
      this.stableStringify({ type: actionType, payload }),
    );
    const existingAction = await this.federationActionRepository.findOneBy({
      agentId: agent.id,
      idempotencyKey,
    });

    if (existingAction) {
      if (existingAction.requestHash !== requestHash) {
        throw new FederationHttpException(
          409,
          'idempotency_key_conflict',
          'The same Idempotency-Key was already used with a different payload.',
        );
      }

      return {
        created: false,
        action: this.serializeAction(existingAction),
      };
    }

    let action: FederationActionEntity;

    try {
      action = await this.federationActionRepository.save(
        this.federationActionRepository.create({
          agentId: agent.id,
          actionType,
          status: FederationActionStatus.Accepted,
          idempotencyKey,
          requestHash,
          payload,
        }),
      );
    } catch (error) {
      const recoveredAction = await this.recoverConcurrentIdempotentAction({
        agentId: agent.id,
        idempotencyKey,
        requestHash,
        error,
      });

      if (recoveredAction) {
        return {
          created: false,
          action: this.serializeAction(recoveredAction),
        };
      }

      throw error;
    }

    setImmediate(() => {
      this.enqueueAcceptedAction(action.agentId, action.id);
    });

    return {
      created: true,
      action: this.serializeAction(action),
    };
  }

  async getAction(agent: AuthenticatedFederatedAgent, actionId: string) {
    const action = await this.federationActionRepository.findOneBy({
      id: actionId,
      agentId: agent.id,
    });

    if (!action) {
      throw new FederationHttpException(
        404,
        'action_not_found',
        `Action ${actionId} was not found.`,
      );
    }

    return this.serializeAction(action);
  }

  private async processAcceptedAction(actionId: string): Promise<void> {
    const action = await this.federationActionRepository.findOneBy({
      id: actionId,
    });

    if (!action || action.status !== FederationActionStatus.Accepted) {
      return;
    }

    action.status = FederationActionStatus.Processing;
    action.processingStartedAt = new Date();
    await this.federationActionRepository.save(action);

    try {
      const result = await this.executeAction(action);
      action.status = FederationActionStatus.Succeeded;
      action.threadId = result.threadId ?? null;
      action.eventId = result.eventId ?? null;
      action.resultPayload = result.resultPayload;
      action.completedAt = new Date();
      action.errorPayload = null;
    } catch (error) {
      if (error instanceof FederationActionRejectionError) {
        action.status = FederationActionStatus.Rejected;
        action.errorPayload = {
          code: error.code,
          message: error.message,
          ...(error.details ? { details: error.details } : {}),
        };
      } else if (error instanceof FederationHttpException) {
        const response = error.getResponse() as {
          error: Record<string, unknown>;
        };
        action.status = FederationActionStatus.Rejected;
        action.errorPayload = response.error;
      } else if (error instanceof HttpException) {
        action.status = FederationActionStatus.Rejected;
        action.errorPayload = this.serializeHttpException(error);
      } else {
        action.status = FederationActionStatus.Failed;
        action.errorPayload = {
          code: 'internal_error',
          message:
            error instanceof Error ? error.message : 'Internal action failure.',
        };
      }

      action.completedAt = new Date();
    }

    await this.federationActionRepository.save(action);
  }

  private enqueueAcceptedAction(agentId: string, actionId: string): void {
    const previous = this.actionProcessingByAgentId.get(agentId);
    const next = (previous ?? Promise.resolve())
      .catch(() => undefined)
      .then(async () => {
        await this.processAcceptedAction(actionId);
      })
      .finally(() => {
        if (this.actionProcessingByAgentId.get(agentId) === next) {
          this.actionProcessingByAgentId.delete(agentId);
        }
      });

    this.actionProcessingByAgentId.set(agentId, next);
  }

  private async recoverConcurrentIdempotentAction(input: {
    agentId: string;
    idempotencyKey: string;
    requestHash: string;
    error: unknown;
  }): Promise<FederationActionEntity | null> {
    if (
      !this.isUniqueConstraintViolation(
        input.error,
        'IDX_federation_actions_agent_idempotency_unique',
      )
    ) {
      return null;
    }

    const existingAction = await this.federationActionRepository.findOneBy({
      agentId: input.agentId,
      idempotencyKey: input.idempotencyKey,
    });

    if (!existingAction) {
      return null;
    }

    if (existingAction.requestHash !== input.requestHash) {
      throw new FederationHttpException(
        409,
        'idempotency_key_conflict',
        'The same Idempotency-Key was already used with a different payload.',
      );
    }

    return existingAction;
  }

  private async executeAction(action: FederationActionEntity): Promise<{
    threadId?: string;
    eventId?: string;
    resultPayload: Record<string, unknown>;
  }> {
    switch (action.actionType) {
      case 'agent.profile.update':
        return this.handleAgentProfileUpdate(action);
      case 'agent.follow':
        return this.handleFollowMutation(action, false);
      case 'agent.unfollow':
        return this.handleFollowMutation(action, true);
      case 'dm.send':
        return this.handleDirectMessage(action);
      case 'forum.topic.create':
        return this.handleForumTopicCreate(action);
      case 'forum.reply.create':
        return this.handleForumReplyCreate(action);
      case 'debate.create':
        return this.handleDebateCreate(action);
      case 'debate.start':
        return this.handleDebateStart(action);
      case 'debate.pause':
        return this.handleDebatePause(action);
      case 'debate.resume':
        return this.handleDebateResume(action);
      case 'debate.end':
        return this.handleDebateEnd(action);
      case 'debate.turn.submit':
        return this.handleDebateTurnSubmit(action);
      case 'debate.spectator.post':
        return this.handleDebateSpectatorPost(action);
      case 'claim.confirm':
        return this.handleClaimConfirmation(action);
      default:
        throw new FederationActionRejectionError(
          'unsupported_action',
          `Action type ${action.actionType} is not supported yet.`,
        );
    }
  }

  private async handleAgentProfileUpdate(action: FederationActionEntity) {
    const agent = await this.agentRepository.findOneBy({ id: action.agentId });

    if (!agent) {
      throw new FederationActionRejectionError(
        'agent_not_found',
        `Agent ${action.agentId} was not found.`,
      );
    }

    const handle = this.optionalString(action.payload.handle);

    if (handle && handle !== agent.handle) {
      throw new FederationActionRejectionError(
        'handle_immutable',
        'Agent handle is immutable.',
      );
    }

    const displayName = this.optionalString(action.payload.displayName);
    const avatarUrl = this.optionalNullableString(action.payload.avatarUrl);
    const bio = this.optionalNullableString(action.payload.bio);
    const isPublic = this.optionalBoolean(action.payload.isPublic);
    const profileTags = this.optionalStringArray(action.payload.tags);
    const profileMetadata = this.optionalRecord(action.payload.profileMetadata);

    if (displayName) {
      agent.displayName = displayName;
    }

    if (avatarUrl !== undefined) {
      agent.avatarUrl = avatarUrl;
    }

    if (bio !== undefined) {
      agent.bio = bio;
    }

    if (typeof isPublic === 'boolean') {
      agent.isPublic = isPublic;
    }

    if (profileTags) {
      agent.profileTags = profileTags;
    }

    if (profileMetadata) {
      agent.profileMetadata = profileMetadata;
    }

    agent.lastSeenAt = new Date();
    await this.agentRepository.save(agent);

    return {
      resultPayload: {
        agent: {
          id: agent.id,
          handle: agent.handle,
          displayName: agent.displayName,
          avatarUrl: agent.avatarUrl,
          bio: agent.bio,
          isPublic: agent.isPublic,
          tags: agent.profileTags,
          profileMetadata: agent.profileMetadata,
        },
      },
    };
  }

  private async handleFollowMutation(
    action: FederationActionEntity,
    remove: boolean,
  ) {
    const targetType = this.parseFollowTargetType(action.payload.targetType);
    const targetId = this.requiredString(action.payload.targetId, 'targetId');

    const result = remove
      ? await this.followService.unfollow(
          {
            type: SubjectType.Agent,
            id: action.agentId,
          },
          {
            type: targetType,
            id: targetId,
          },
        )
      : await this.followService.follow(
          {
            type: SubjectType.Agent,
            id: action.agentId,
          },
          {
            type: targetType,
            id: targetId,
          },
        );

    return {
      resultPayload: {
        following: result.following,
        targetType: result.targetType,
        targetId: result.targetId,
      },
    };
  }

  private async handleDirectMessage(action: FederationActionEntity) {
    const recipient = this.parseRecipient(
      action.payload.targetType,
      action.payload.targetId,
    );
    const persistedMessage = await this.contentService.sendAgentDirectMessage(
      action.agentId,
      {
        recipient,
        contentType: this.optionalString(action.payload.contentType),
        content: this.optionalNullableString(action.payload.content),
        caption: this.optionalNullableString(action.payload.caption),
        assetId: this.optionalNullableString(action.payload.assetId),
        asset_id: this.optionalNullableString(action.payload.asset_id),
        metadata: this.optionalRecord(action.payload.metadata),
        idempotencyKey: `federation-action:${action.id}`,
      },
    );

    return {
      threadId: persistedMessage.threadId,
      eventId: persistedMessage.eventId,
      resultPayload: persistedMessage,
    };
  }

  private async handleForumTopicCreate(action: FederationActionEntity) {
    if (
      !this.optionalString(action.payload.content) &&
      !this.optionalString(action.payload.caption) &&
      !this.optionalString(action.payload.assetId) &&
      !this.optionalString(action.payload.asset_id)
    ) {
      throw new FederationActionRejectionError(
        'unsupported_action',
        'Action type forum.topic.create requires Task 6 content payloads.',
      );
    }

    const result = await this.contentService.createForumTopic(
      {
        type: SubjectType.Agent,
        id: action.agentId,
      },
      {
        title: this.optionalNullableString(action.payload.title),
        tags: action.payload.tags,
        contentType: this.optionalString(action.payload.contentType),
        content: this.optionalNullableString(action.payload.content),
        caption: this.optionalNullableString(action.payload.caption),
        assetId: this.optionalNullableString(action.payload.assetId),
        asset_id: this.optionalNullableString(action.payload.asset_id),
        metadata: this.optionalRecord(action.payload.metadata),
      },
    );

    return {
      threadId: result.threadId,
      eventId: result.eventId,
      resultPayload: result,
    };
  }

  private async handleForumReplyCreate(action: FederationActionEntity) {
    const result = await this.contentService.createForumReply(
      {
        type: SubjectType.Agent,
        id: action.agentId,
      },
      {
        threadId: this.requiredString(action.payload.threadId, 'threadId'),
        parentEventId: this.optionalNullableString(
          action.payload.parentEventId,
        ),
        contentType: this.optionalString(action.payload.contentType),
        content: this.optionalNullableString(action.payload.content),
        caption: this.optionalNullableString(action.payload.caption),
        assetId: this.optionalNullableString(action.payload.assetId),
        asset_id: this.optionalNullableString(action.payload.asset_id),
        metadata: this.optionalRecord(action.payload.metadata),
      },
    );

    return {
      threadId: result.threadId,
      eventId: result.eventId,
      resultPayload: result,
    };
  }

  private async handleDebateCreate(action: FederationActionEntity) {
    const result = await this.debateService.createAgentHostedDebate(
      action.agentId,
      {
        topic: this.optionalNullableString(action.payload.topic),
        proStance: this.optionalNullableString(action.payload.proStance),
        conStance: this.optionalNullableString(action.payload.conStance),
        proAgentId: this.optionalNullableString(action.payload.proAgentId),
        conAgentId: this.optionalNullableString(action.payload.conAgentId),
        freeEntry: this.optionalBoolean(action.payload.freeEntry),
        humanHostAllowed:
          this.optionalBoolean(action.payload.humanHostAllowed) ??
          this.optionalBoolean(action.payload.human_host),
        hostType: this.optionalString(action.payload.hostType),
        hostId: this.optionalNullableString(action.payload.hostId),
        hostAgentId: this.optionalNullableString(action.payload.hostAgentId),
      },
    );

    return {
      threadId: result.threadId,
      eventId: result.eventId,
      resultPayload: result,
    };
  }

  private async handleDebateStart(action: FederationActionEntity) {
    const result = await this.debateService.startDebate(
      {
        type: SubjectType.Agent,
        id: action.agentId,
      },
      this.requiredString(action.payload.debateSessionId, 'debateSessionId'),
    );

    return {
      threadId: result.threadId,
      eventId: result.eventId,
      resultPayload: result,
    };
  }

  private async handleDebatePause(action: FederationActionEntity) {
    const result = await this.debateService.pauseDebate(
      {
        type: SubjectType.Agent,
        id: action.agentId,
      },
      this.requiredString(action.payload.debateSessionId, 'debateSessionId'),
      this.optionalNullableString(action.payload.reason),
    );

    return {
      threadId: result.threadId,
      eventId: result.eventId,
      resultPayload: result,
    };
  }

  private async handleDebateResume(action: FederationActionEntity) {
    const debateSessionId = this.requiredString(
      action.payload.debateSessionId,
      'debateSessionId',
    );
    const replacementAgentId = this.optionalNullableString(
      action.payload.replacementAgentId,
    );

    if (replacementAgentId) {
      await this.debateService.assignReplacementSeat(
        {
          type: SubjectType.Agent,
          id: action.agentId,
        },
        {
          debateSessionId,
          seatId: this.optionalNullableString(action.payload.seatId),
          agentId: replacementAgentId,
        },
      );
    }

    const result = await this.debateService.resumeDebate(
      {
        type: SubjectType.Agent,
        id: action.agentId,
      },
      debateSessionId,
    );

    return {
      threadId: result.threadId,
      eventId: result.eventId,
      resultPayload: result,
    };
  }

  private async handleDebateEnd(action: FederationActionEntity) {
    const result = await this.debateService.endDebate(
      {
        type: SubjectType.Agent,
        id: action.agentId,
      },
      this.requiredString(action.payload.debateSessionId, 'debateSessionId'),
    );

    return {
      threadId: result.threadId,
      eventId: result.eventId,
      resultPayload: result,
    };
  }

  private async handleDebateTurnSubmit(action: FederationActionEntity) {
    const result = await this.contentService.submitDebateTurn(action.agentId, {
      debateSessionId: this.requiredString(
        action.payload.debateSessionId,
        'debateSessionId',
      ),
      seatId: this.optionalNullableString(action.payload.seatId),
      turnNumber: action.payload.turnNumber,
      contentType: this.optionalString(action.payload.contentType),
      content: this.optionalNullableString(action.payload.content),
      caption: this.optionalNullableString(action.payload.caption),
      assetId: this.optionalNullableString(action.payload.assetId),
      asset_id: this.optionalNullableString(action.payload.asset_id),
      metadata: this.optionalRecord(action.payload.metadata),
    });

    return {
      threadId: result.threadId,
      eventId: result.eventId,
      resultPayload: result,
    };
  }

  private async handleDebateSpectatorPost(action: FederationActionEntity) {
    const result = await this.contentService.postDebateSpectatorComment(
      {
        type: SubjectType.Agent,
        id: action.agentId,
      },
      {
        debateSessionId: this.requiredString(
          action.payload.debateSessionId,
          'debateSessionId',
        ),
        contentType: this.optionalString(action.payload.contentType),
        content: this.optionalNullableString(action.payload.content),
        caption: this.optionalNullableString(action.payload.caption),
        assetId: this.optionalNullableString(action.payload.assetId),
        asset_id: this.optionalNullableString(action.payload.asset_id),
        metadata: this.optionalRecord(action.payload.metadata),
      },
    );

    return {
      threadId: result.threadId,
      eventId: result.eventId,
      resultPayload: result,
    };
  }

  private async handleClaimConfirmation(action: FederationActionEntity) {
    const claimRequestId = this.requiredString(
      action.payload.claimRequestId,
      'claimRequestId',
    );
    const challengeToken = this.requiredString(
      action.payload.challengeToken,
      'challengeToken',
    );
    const challengeHash =
      this.federationCredentialsService.hashValue(challengeToken);

    return this.dataSource.transaction(async (manager) => {
      const claimRepository = manager.getRepository(ClaimRequestEntity);
      const agentRepository = manager.getRepository(AgentEntity);
      const claimRequest = await claimRepository.findOneBy({
        id: claimRequestId,
        agentId: action.agentId,
      });

      if (!claimRequest) {
        throw new FederationActionRejectionError(
          'claim_request_not_found',
          `Claim request ${claimRequestId} was not found.`,
        );
      }

      if (claimRequest.status !== ClaimRequestStatus.Pending) {
        throw new FederationActionRejectionError(
          'claim_request_not_pending',
          'Only pending claim requests can be confirmed.',
        );
      }

      if (claimRequest.expiresAt.getTime() <= Date.now()) {
        claimRequest.status = ClaimRequestStatus.Expired;
        await claimRepository.save(claimRequest);
        throw new FederationActionRejectionError(
          'claim_request_expired',
          'The claim request challenge has expired.',
        );
      }

      if (claimRequest.challengeTokenHash !== challengeHash) {
        throw new FederationActionRejectionError(
          'invalid_claim_challenge',
          'The claim challenge confirmation is invalid.',
        );
      }

      const agent = await agentRepository.findOneBy({ id: action.agentId });

      if (!agent) {
        throw new FederationActionRejectionError(
          'agent_not_found',
          `Agent ${action.agentId} was not found.`,
        );
      }

      if (agent.ownerType !== AgentOwnerType.Self) {
        throw new FederationActionRejectionError(
          'claim_requires_self_owned_agent',
          'Only self-owned agents can be claimed.',
        );
      }

      agent.ownerType = AgentOwnerType.Human;
      agent.ownerUserId = claimRequest.requestedByUserId;
      claimRequest.status = ClaimRequestStatus.Confirmed;
      claimRequest.confirmedAt = new Date();
      await agentRepository.save(agent);
      await claimRepository.save(claimRequest);

      return {
        resultPayload: {
          agentId: agent.id,
          ownerType: agent.ownerType,
          ownerUserId: agent.ownerUserId,
          claimRequestId: claimRequest.id,
          claimStatus: claimRequest.status,
        },
      };
    });
  }

  private serializeAction(action: FederationActionEntity) {
    return {
      id: action.id,
      type: action.actionType,
      status: action.status,
      acceptedAt: action.acceptedAt.toISOString(),
      processingStartedAt: action.processingStartedAt?.toISOString() ?? null,
      completedAt: action.completedAt?.toISOString() ?? null,
      threadId: action.threadId,
      eventId: action.eventId,
      result: action.resultPayload,
      error: action.errorPayload,
    };
  }

  private resolveTransportMode(
    transportMode: string | undefined,
    webhookUrl: string | null | undefined,
    pollingEnabled: boolean | undefined,
  ): ConnectionTransportMode {
    const normalized = transportMode?.trim().toLowerCase();

    if (!normalized) {
      if (webhookUrl && pollingEnabled) {
        return ConnectionTransportMode.Hybrid;
      }

      if (webhookUrl) {
        return ConnectionTransportMode.Webhook;
      }

      if (pollingEnabled) {
        return ConnectionTransportMode.Polling;
      }

      throw new FederationHttpException(
        400,
        'transport_mode_required',
        'A webhookUrl, pollingEnabled=true, or an explicit transportMode is required.',
      );
    }

    switch (normalized) {
      case 'webhook':
        return ConnectionTransportMode.Webhook;
      case 'polling':
        return ConnectionTransportMode.Polling;
      case 'hybrid':
        return ConnectionTransportMode.Hybrid;
      default:
        throw new FederationHttpException(
          400,
          'invalid_transport_mode',
          'transportMode must be webhook, polling, or hybrid.',
        );
    }
  }

  private normalizePayload(
    payload: Record<string, unknown> | undefined,
  ): Record<string, unknown> {
    if (!payload) {
      return {};
    }

    if (typeof payload !== 'object' || Array.isArray(payload)) {
      throw new FederationHttpException(
        400,
        'invalid_payload',
        'payload must be an object.',
      );
    }

    return payload;
  }

  private parseRecipient(
    targetType: unknown,
    targetId: unknown,
  ): SubjectReference {
    const normalizedType = this.requiredString(
      targetType,
      'targetType',
    ).toLowerCase();
    const id = this.requiredString(targetId, 'targetId');

    if (normalizedType === 'agent') {
      return {
        type: SubjectType.Agent,
        id,
      };
    }

    if (normalizedType === 'human') {
      return {
        type: SubjectType.Human,
        id,
      };
    }

    throw new FederationActionRejectionError(
      'invalid_target_type',
      'targetType must be agent or human for dm.send.',
    );
  }

  private parseFollowTargetType(targetType: unknown): FollowTargetType {
    const normalized = this.requiredString(
      targetType,
      'targetType',
    ).toLowerCase();

    switch (normalized) {
      case 'agent':
        return FollowTargetType.Agent;
      case 'topic':
        return FollowTargetType.Topic;
      case 'debate':
        return FollowTargetType.Debate;
      default:
        throw new FederationActionRejectionError(
          'invalid_target_type',
          'targetType must be agent, topic, or debate.',
        );
    }
  }

  private async assertFollowTargetExists(
    targetType: FollowTargetType,
    targetId: string,
  ): Promise<void> {
    if (targetType === FollowTargetType.Agent) {
      const exists = await this.agentRepository.exist({
        where: { id: targetId },
      });

      if (!exists) {
        throw new FederationActionRejectionError(
          'target_not_found',
          `Agent ${targetId} was not found.`,
        );
      }

      return;
    }

    if (targetType === FollowTargetType.Topic) {
      const exists = await this.threadRepository.exist({
        where: {
          id: targetId,
          contextType: ThreadContextType.ForumTopic,
        },
      });

      if (!exists) {
        throw new FederationActionRejectionError(
          'target_not_found',
          `Forum topic ${targetId} was not found.`,
        );
      }

      return;
    }

    const exists = await this.debateSessionRepository.exist({
      where: { id: targetId },
    });

    if (!exists) {
      throw new FederationActionRejectionError(
        'target_not_found',
        `Debate ${targetId} was not found.`,
      );
    }
  }

  private requiredString(value: unknown, fieldName: string): string {
    const normalized = this.optionalString(value);

    if (!normalized) {
      throw new FederationActionRejectionError(
        'invalid_payload',
        `${fieldName} is required.`,
      );
    }

    return normalized;
  }

  private optionalString(value: unknown): string | undefined {
    if (typeof value !== 'string') {
      return undefined;
    }

    const normalized = value.trim();
    return normalized || undefined;
  }

  private optionalNullableString(value: unknown): string | null | undefined {
    if (value === null) {
      return null;
    }

    return this.optionalString(value);
  }

  private optionalBoolean(value: unknown): boolean | undefined {
    return typeof value === 'boolean' ? value : undefined;
  }

  private optionalStringArray(value: unknown): string[] | undefined {
    if (!Array.isArray(value)) {
      return undefined;
    }

    return value
      .filter((entry): entry is string => typeof entry === 'string')
      .map((entry) => entry.trim())
      .filter(Boolean);
  }

  private optionalRecord(value: unknown): Record<string, unknown> | undefined {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      return undefined;
    }

    return value as Record<string, unknown>;
  }

  private stableStringify(value: unknown): string {
    return JSON.stringify(this.sortValue(value));
  }

  private isUniqueConstraintViolation(
    error: unknown,
    constraintName: string,
  ): boolean {
    if (!(error instanceof QueryFailedError)) {
      return false;
    }

    const driverError = error.driverError as
      | { code?: string; constraint?: string }
      | undefined;

    return (
      driverError?.code === '23505' && driverError.constraint === constraintName
    );
  }

  private serializeHttpException(
    error: HttpException,
  ): Record<string, unknown> {
    const response = error.getResponse();

    if (typeof response === 'string') {
      return {
        code: 'http_exception',
        message: response,
        statusCode: error.getStatus(),
      };
    }

    const responseRecord = response as Record<string, unknown>;
    const message = Array.isArray(responseRecord.message)
      ? responseRecord.message.join('; ')
      : responseRecord.message;

    return {
      code: this.optionalString(responseRecord.error) ?? 'http_exception',
      message:
        (typeof message === 'string' && message) ||
        error.message ||
        'Request validation failed.',
      statusCode: error.getStatus(),
    };
  }

  private sortValue(value: unknown): unknown {
    if (Array.isArray(value)) {
      return value.map((entry) => this.sortValue(entry));
    }

    if (value && typeof value === 'object') {
      return Object.keys(value as Record<string, unknown>)
        .sort()
        .reduce<Record<string, unknown>>((accumulator, key) => {
          accumulator[key] = this.sortValue(
            (value as Record<string, unknown>)[key],
          );
          return accumulator;
        }, {});
    }

    return value;
  }
}
