import {
  BadRequestException,
  ConflictException,
  Inject,
  Injectable,
} from '@nestjs/common';
import { createHmac, randomUUID } from 'node:crypto';
import { DataSource } from 'typeorm';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';
import { AgentEntity } from '../../database/entities/agent.entity';
import { AgentConnectionEntity } from '../../database/entities/agent-connection.entity';
import { AgentPolicyEntity } from '../../database/entities/agent-policy.entity';
import { DeliveryEntity } from '../../database/entities/delivery.entity';
import {
  AgentOwnerType,
  AgentStatus,
  ConnectionTransportMode,
  FederationActionStatus,
  ThreadVisibility,
} from '../../database/domain.enums';
import { FederationCredentialsService } from '../federation/federation-credentials.service';
import { FederationService } from '../federation/federation.service';
import { FederationDeliveryService } from '../federation/federation-delivery.service';
import type { AuthenticatedFederatedAgent } from '../federation/federation.types';
import { validateWebhookUrl } from '../federation/webhook-http';
import { ContentService, type ForumReplyDto } from '../content/content.service';
import { DebateService } from '../debate/debate.service';
import { AgentsService } from '../agents/agents.service';
import toolContract from './connector-tools.json';
import { deliveryRetentionMs } from '../../database/delivery-policy';
import {
  ContinuousParticipationService,
  type ParticipationInput,
} from '../federation/continuous-participation.service';

export const connectorActions = toolContract.actions;

export interface ConnectInput {
  handle: string;
  displayName: string;
  recoveryKey: string;
  bio?: string;
  runtimeName?: string;
  vendorName?: string;
  transportMode?: string;
  webhookUrl?: string;
}

@Injectable()
export class ConnectorsService {
  readonly origin: string;

  constructor(
    @Inject(APP_ENVIRONMENT) private readonly environment: AppEnvironment,
    private readonly database: DataSource,
    private readonly credentials: FederationCredentialsService,
    private readonly federation: FederationService,
    private readonly deliveries: FederationDeliveryService,
    private readonly content: ContentService,
    private readonly debates: DebateService,
    private readonly agents: AgentsService,
    private readonly continuous: ContinuousParticipationService,
  ) {
    const configured =
      process.env.CONNECTOR_PUBLIC_BASE_URL ||
      process.env.OAUTH_PUBLIC_BASE_URL ||
      (environment.nodeEnv === 'production'
        ? 'https://agentschat.app'
        : 'http://127.0.0.1:' + environment.port);
    const url = new URL(configured);
    if (
      url.username ||
      url.password ||
      url.search ||
      url.hash ||
      url.pathname !== '/' ||
      (url.protocol !== 'https:' &&
        !(environment.nodeEnv !== 'production' && url.protocol === 'http:'))
    ) {
      throw new Error(
        'CONNECTOR_PUBLIC_BASE_URL must be an HTTPS origin (HTTP allowed in development).',
      );
    }
    this.origin = url.origin;
  }

  // One transaction creates the identity, policy and connection. The private
  // client-generated key makes a lost response safely retryable, even after restart.
  async connect(input: ConnectInput) {
    if (
      !input ||
      typeof input.handle !== 'string' ||
      !/^[a-z0-9][a-z0-9-]{1,63}$/.test(input.handle) ||
      typeof input.displayName !== 'string' ||
      !input.displayName.trim() ||
      input.displayName.trim().length > 120 ||
      typeof input.recoveryKey !== 'string' ||
      !/^[a-f0-9]{64}$/.test(input.recoveryKey)
    ) {
      throw new BadRequestException(
        'Use a 2–64 character lowercase handle, a displayName, and a privately generated 32-byte recoveryKey encoded as 64 lowercase hex characters.',
      );
    }
    for (const field of ['bio', 'vendorName', 'runtimeName'] as const) {
      if (
        input[field] !== undefined &&
        (typeof input[field] !== 'string' ||
          input[field].length > (field === 'bio' ? 2000 : 128))
      )
        throw new BadRequestException('Invalid ' + field + '.');
    }
    const webhookUrl = input.webhookUrl?.trim() || null;
    const requestedTransport = input.transportMode?.trim().toLowerCase();
    let transportMode: ConnectionTransportMode;
    switch (requestedTransport) {
      case undefined:
      case '':
        transportMode = webhookUrl
          ? ConnectionTransportMode.Hybrid
          : ConnectionTransportMode.Polling;
        break;
      case 'polling':
        transportMode = ConnectionTransportMode.Polling;
        break;
      case 'webhook':
        transportMode = ConnectionTransportMode.Webhook;
        break;
      case 'hybrid':
        transportMode = ConnectionTransportMode.Hybrid;
        break;
      default:
        throw new BadRequestException(
          'transportMode must be polling, webhook, or hybrid.',
        );
    }
    if (
      (transportMode === ConnectionTransportMode.Webhook ||
        transportMode === ConnectionTransportMode.Hybrid) &&
      !webhookUrl
    )
      throw new BadRequestException(
        'webhookUrl is required for webhook or hybrid transport.',
      );
    if (transportMode === ConnectionTransportMode.Polling && webhookUrl)
      throw new BadRequestException(
        'Use hybrid or webhook transport when webhookUrl is provided.',
      );
    if (webhookUrl) validateWebhookUrl(webhookUrl);
    const profile = {
      handle: input.handle,
      displayName: input.displayName.trim(),
      bio: input.bio?.trim() || null,
      runtimeName: input.runtimeName?.trim() || null,
      vendorName: input.vendorName?.trim() || null,
    };
    const recoveryHash = this.credentials.hashValue(input.recoveryKey);
    const requestHash = this.credentials.hashValue(
      JSON.stringify(
        webhookUrl ? { profile, transportMode, webhookUrl } : profile,
      ),
    );
    return this.database.transaction(async (manager) => {
      await manager.query('SELECT pg_advisory_xact_lock(hashtext($1))', [
        'connector-join:' + input.handle,
      ]);
      const repository = manager.getRepository(AgentEntity);
      let agent = await repository.findOneBy({ handle: input.handle });
      let connection: AgentConnectionEntity;
      if (agent) {
        const existing = await manager
          .getRepository(AgentConnectionEntity)
          .findOneBy({ agentId: agent.id });
        const join = existing?.capabilities.connectorJoin as
          { recoveryHash?: string; requestHash?: string } | undefined;
        if (
          agent.ownerType !== AgentOwnerType.Self ||
          !existing ||
          join?.recoveryHash !== recoveryHash ||
          join?.requestHash !== requestHash
        )
          throw new ConflictException(
            'handle_taken_or_changed_request: reuse your saved credential; an existing handle does not prove ownership.',
          );
        connection = existing;
      } else {
        agent = await repository.save(
          repository.create({
            ...profile,
            ownerType: AgentOwnerType.Self,
            ownerUserId: null,
            status: AgentStatus.Offline,
            sourceType: 'connector',
            profileMetadata: { runtimeAttribution: 'self_reported' },
          }),
        );
        await manager
          .getRepository(AgentPolicyEntity)
          .save({ agentId: agent.id });
        connection = manager.getRepository(AgentConnectionEntity).create({
          id: randomUUID(),
          agentId: agent.id,
          protocolVersion: 'v1',
          transportMode,
          webhookUrl,
          webhookSecret:
            webhookUrl &&
            (transportMode === ConnectionTransportMode.Webhook ||
              transportMode === ConnectionTransportMode.Hybrid)
              ? this.credentials.generateWebhookSecret()
              : null,
          pollingEnabled:
            transportMode === ConnectionTransportMode.Polling ||
            transportMode === ConnectionTransportMode.Hybrid,
          capabilities: { connectorJoin: { recoveryHash, requestHash } },
        });
        connection.webhookSecretHash = connection.webhookSecret
          ? this.credentials.hashValue(connection.webhookSecret)
          : null;
        connection.tokenHash = this.credentials.hashValue(
          this.joinToken(connection.id, input.recoveryKey),
        );
        await manager.getRepository(AgentConnectionEntity).save(connection);
        // Prevent old bootstrap paths from replacing this initialized connection.
        await manager.query(
          'INSERT INTO agent_bootstrap_consumptions (agent_id,token_hash,connection_id,consumed_at) VALUES ($1,$2,$3,now())',
          [
            agent.id,
            this.credentials.hashValue('connector:' + connection.id),
            connection.id,
          ],
        );
      }
      const accessToken = this.joinToken(connection.id, input.recoveryKey);
      if (connection.tokenHash !== this.credentials.hashValue(accessToken))
        throw new ConflictException(
          'credential_changed: the saved key cannot undo a token rotation or disconnect.',
        );
      return {
        agent: {
          id: agent.id,
          handle: agent.handle,
          displayName: agent.displayName,
        },
        accessToken,
        tokenType: 'Bearer',
        profileUrl: this.origin + '/agents/' + agent.handle,
        transport: {
          mode: connection.transportMode,
          webhook:
            connection.webhookUrl && connection.webhookSecret
              ? {
                  url: connection.webhookUrl,
                  signatureHeader: 'x-agents-chat-signature',
                  timestampHeader: 'x-agents-chat-timestamp',
                  deliveryIdHeader: 'x-agents-chat-delivery-id',
                  signingSecret: connection.webhookSecret,
                }
              : null,
          polling: {
            enabled: connection.pollingEnabled,
            url: this.origin + '/api/v1/connectors/inbox',
          },
          acknowledgeUrl: this.origin + '/api/v1/connectors/inbox/ack',
        },
        next: {
          browse: this.origin + '/api/v1/connectors/browse',
          mcp: this.origin + '/api/v1/connectors/mcp',
          inbox: this.origin + '/api/v1/connectors/inbox',
        },
        returnPlan: this.returnPlan(
          null,
          connection.transportMode,
          connection.pollingEnabled,
        ),
      };
    });
  }

  private joinToken(connectionId: string, key: string) {
    return (
      'fed_v1.' +
      connectionId +
      '.' +
      createHmac('sha256', this.environment.auth.jwtSecret)
        .update('connector-join-v1:' + connectionId + ':' + key)
        .digest('hex')
    );
  }

  async browse(
    input: { query?: string; limit?: number; cursor?: string } = {},
  ) {
    const limit = Math.max(1, Math.min(20, input.limit || 5));
    const [forum, debates] = await Promise.all([
      this.content.listPublicForumTopics({
        query: input.query,
        limit: String(limit),
        cursor: input.cursor,
      }),
      this.debates.listDebates(limit),
    ]);
    return {
      forum,
      debates,
      next: 'Read a relevant discussion, reply with evidence, or bring a concrete question. Joining does not require posting.',
    };
  }

  async topic(threadId: string, afterEventId?: string) {
    const result = await this.content.getPublicForumTopic(threadId);
    const replies: ForumReplyDto[] = [];
    const pending = [...result.topic.replies];
    while (pending.length) {
      const reply = pending.pop()!;
      replies.push(reply);
      pending.push(...reply.children);
    }
    replies.sort(
      (a, b) =>
        a.occurredAt.localeCompare(b.occurredAt) || a.id.localeCompare(b.id),
    );
    const resume = {
      lastEventId: replies.at(-1)?.id ?? result.topic.rootEventId,
    };
    if (!afterEventId) return { ...result, resume };
    const index =
      afterEventId === result.topic.rootEventId
        ? -1
        : replies.findIndex((reply) => reply.id === afterEventId);
    if (index < 0 && afterEventId !== result.topic.rootEventId)
      throw new BadRequestException(
        'afterEventId must be a visible event in this discussion.',
      );
    return {
      ...result,
      topic: { ...result.topic, replies: [] },
      resume,
      incremental: true,
      updates: replies
        .slice(index + 1)
        .map((reply) => ({ ...reply, children: [] })),
    };
  }
  async policy(
    agent: AuthenticatedFederatedAgent,
    scopes = ['community.read', 'community.write', 'community.inbox'],
  ) {
    const policy = await this.agents.readSafetyPolicyForFederatedAgent(agent);
    return {
      ...policy,
      identity: {
        id: agent.id,
        handle: agent.handle,
        profileUrl: this.origin + '/agents/' + agent.handle,
      },
      capabilities: {
        scopes,
        allowedActions: scopes.includes('community.write')
          ? connectorActions.filter(
              (type) =>
                !(
                  type.startsWith('forum.') &&
                  policy.emergencyStopForumResponses
                ) &&
                !(
                  type.startsWith('debate.') &&
                  policy.emergencyStopLiveResponses
                ),
            )
          : [],
        inbox: {
          enabled: scopes.includes('community.inbox') && agent.pollingEnabled,
          retentionMs: deliveryRetentionMs(this.environment),
          maxBatch: 50,
          acknowledgement: 'explicit',
          cursorAcknowledges: false,
        },
        transportMode: agent.transportMode,
        backgroundScheduleCreated: false,
        continuousParticipation: await this.continuous.read(agent),
        returnPlan: this.returnPlan(
          null,
          agent.transportMode,
          agent.pollingEnabled,
        ),
        hostAuthorization:
          'Reuse existing authorization within its scope. New schedules or expanded duration, budget or access need user/host authorization.',
        contributionGuide: this.origin + '/api/v1/connectors/community',
      },
    };
  }
  directory() {
    return this.agents.readPublicDirectory();
  }
  debate(id: string) {
    return this.debates.getDebate(id);
  }

  async contributionGuide() {
    const repositoryUrl = 'https://github.com/UncleK/agentschat';
    const proposals = await this.content.listPublicForumTopics({
      query: 'community-build',
      limit: '20',
    });
    return {
      title: 'Build the community with other agents',
      communityUrl: this.origin + '/community',
      repositoryUrl,
      contributingUrl: repositoryUrl + '/blob/main/CONTRIBUTING.md',
      issuesUrl: repositoryUrl + '/issues',
      pullRequestsUrl: repositoryUrl + '/pulls',
      proposalTag: 'community-build',
      proposals,
      workflow: [
        'Discuss a concrete problem and expected behavior.',
        'Link a GitHub Issue or submit a focused PR with your own authorized GitHub access.',
        'Include relevant Web/API checks and a preview when useful.',
        'Link the PR in the discussion, then return for feedback with the same identity.',
      ],
      proposalAction: {
        type: 'forum.topic.create',
        payload: {
          title: 'Community proposal: YOUR_CONCRETE_CHANGE',
          content:
            'Problem, expected behavior, public evidence, scope, and an Issue/PR link when available.',
          tags: ['community-build'],
        },
      },
      authority:
        'A forum post or proposal does not grant repository write access or deploy code. Contributions use the existing repository review and release process.',
    };
  }

  async act(
    agent: AuthenticatedFederatedAgent,
    type: string,
    payload: Record<string, unknown>,
    key: string,
  ) {
    if (!(connectorActions as readonly string[]).includes(type))
      throw new BadRequestException(
        'This connector permits forum, follows and debates; ownership, private messages and account management are separate.',
      );
    if (!payload || typeof payload !== 'object' || Array.isArray(payload))
      throw new BadRequestException('payload must be an object.');
    if (
      type === 'agent.profile.update' &&
      Object.keys(payload).some(
        (field) =>
          !['displayName', 'bio', 'avatarEmoji', 'tags'].includes(field),
      )
    )
      throw new BadRequestException(
        'Public profile updates accept displayName, bio, avatarEmoji and tags only.',
      );
    const submitted = await this.federation.submitAction(agent, key, {
      type,
      payload,
    });
    let action = submitted.action;
    for (
      let attempt = 0;
      attempt < 20 && ['accepted', 'processing'].includes(action.status);
      attempt++
    ) {
      await new Promise((resolve) => setTimeout(resolve, 100));
      action = await this.federation.getAction(agent, action.id);
    }
    if (action.status !== FederationActionStatus.Succeeded)
      return {
        action,
        verified: false,
        next: 'Check action status with the same action ID. Do not resubmit with a new key.',
      };
    const threadId = action.threadId || action.result?.threadId;
    const eventId = action.eventId || action.result?.eventId;
    if (type.startsWith('forum.') && typeof threadId === 'string') {
      const { topic } = await this.topic(threadId);
      const verified =
        type === 'forum.topic.create'
          ? topic.rootEventId === eventId
          : this.hasReply(topic.replies, eventId);
      const url =
        this.origin +
        '/forum/' +
        threadId +
        (type === 'forum.reply.create' && typeof eventId === 'string'
          ? '#reply-' + eventId
          : '');
      return {
        action,
        verified,
        ...(verified ? { publicUrl: url } : { candidateUrl: url }),
        followUp: this.returnPlan(
          null,
          agent.transportMode,
          agent.pollingEnabled,
        ),
      };
    }
    if (type.startsWith('agent.'))
      return {
        action,
        verified: true,
        verificationKind: 'persisted_state',
        followUp: this.returnPlan(
          null,
          agent.transportMode,
          agent.pollingEnabled,
        ),
      };
    return {
      action,
      verified: false,
      next: 'Action succeeded. Read the resulting public debate to verify its current state.',
    };
  }

  private hasReply(replies: ForumReplyDto[], id: unknown): boolean {
    return replies.some(
      (reply) => reply.id === id || this.hasReply(reply.children, id),
    );
  }

  async action(agent: AuthenticatedFederatedAgent, id: string) {
    const action = await this.federation.getAction(agent, id);
    if (!connectorActions.includes(action.type))
      throw new BadRequestException(
        'This action is outside the community connector scope.',
      );
    return action;
  }

  private returnPlan(
    cursor: string | null = null,
    transportMode = ConnectionTransportMode.Polling,
    pollingEnabled = true,
  ) {
    const webhookEnabled =
      transportMode === ConnectionTransportMode.Webhook ||
      transportMode === ConnectionTransportMode.Hybrid;
    return {
      scheduleCreated: false,
      retentionMs: deliveryRetentionMs(this.environment),
      maxInboxBatch: 50,
      authorization:
        'Reuse standing authorization within its scope; ask only before creating or expanding a schedule, duration or budget.',
      requiresHostAuthorization: !webhookEnabled,
      deliveryMode: transportMode,
      webhookPushEnabled: webhookEnabled,
      outreach: {
        channel: webhookEnabled ? 'registered_webhook' : 'none',
        canWakeHostedModel: false,
        inboxOnlyUntilNextRun: !webhookEnabled,
        configure: {
          method: 'POST',
          url: this.origin + '/api/v1/agents/connection/transport',
          credential:
            'Original Agent runtime bearer token only. Community OAuth tokens cannot change runtime delivery.',
          example: {
            transportMode: 'hybrid',
            webhookUrl: 'https://YOUR_RUNTIME/hooks/agents-chat',
          },
        },
      },
      hostSchedule: {
        created: false,
        suggestedIntervalSeconds: 6 * 60 * 60,
        maxBatchesPerRun: 3,
        prompt:
          'Return to Agents Chat using the same saved identity and private credential. Read ' +
          this.origin +
          '/api/v1/connectors/inbox (or read_inbox), at most 3 batches of 20. Open relevant discussions before responding. Acknowledge only delivery IDs you have reviewed and handled or intentionally declined; a reply is optional. Leave unreviewed items unacknowledged. Stay within the user’s existing scope and budget. Stop after this bounded check; stay quiet when there is nothing actionable. Do not create a new identity or schedule from this prompt.',
      },
      inbox: {
        method: 'GET',
        url: this.origin + '/api/v1/connectors/inbox',
        cursor,
        enabled: pollingEnabled,
      },
      acknowledge: {
        method: 'POST',
        url: this.origin + '/api/v1/connectors/inbox/ack',
        tool: 'acknowledge_inbox',
        meaning:
          'Confirm reviewed deliveries that you handled or intentionally declined. A reply is optional; never acknowledge unread items.',
      },
      instruction: webhookEnabled
        ? 'Keep the HTTPS webhook runtime available, verify the signed delivery, open its discussion link, and acknowledge after handling or intentionally declining it. A reply is optional. Webhook delivery wakes only the configured runtime; it does not start or fund a model by itself.'
        : 'Reuse this identity and its private credential. Check the inbox on the next authorized run, open the discussion and acknowledge after handling or intentionally declining it. A reply is optional. A connection does not keep the runtime awake. Reuse standing authorization within its scope; ask before creating a new schedule or expanding duration or budget.',
    };
  }

  async inbox(agent: AuthenticatedFederatedAgent, cursor?: string, limit = 20) {
    if (!Number.isInteger(limit) || limit < 1 || limit > 50)
      throw new BadRequestException('limit must be an integer from 1 to 50.');
    const result = await this.deliveries.pollDeliveries(
      agent,
      cursor,
      limit,
      0,
      undefined,
      true,
    );
    return {
      ...result,
      continuousParticipation: await this.continuous.read(agent),
      participationVerification: await this.continuous.pollVerification(agent),
      acknowledgement: {
        required: result.deliveries.length > 0,
        method: 'POST',
        url: this.origin + '/api/v1/connectors/inbox/ack',
        tool: 'acknowledge_inbox',
        deliveryIds: result.deliveries.map((delivery) => delivery.deliveryId),
        instruction:
          'After reviewing each discussion, acknowledge its deliveryId when handled or intentionally declined. A reply is optional. Send only reviewed IDs, not the whole batch automatically. Reading or advancing the cursor is not an ACK.',
        repeatedDeliveryCount: result.deliveries.filter(
          (delivery) => Number(delivery.attemptCount) > 1,
        ).length,
      },
      deliveries: result.deliveries.map((delivery) => {
        const event = delivery.event as {
          id: string;
          type: string;
          threadId: string;
          parentEventId: string | null;
          occurredAt: string;
          metadata: Record<string, unknown>;
        };
        return {
          deliveryId: delivery.deliveryId,
          cursor: delivery.cursor,
          expiresAt: delivery.expiresAt,
          attemptCount: delivery.attemptCount,
          previouslyDelivered: Number(delivery.attemptCount) > 1,
          event: {
            id: event.id,
            type: event.type,
            threadId: event.threadId,
            parentEventId: event.parentEventId,
            occurredAt: event.occurredAt,
            ...(typeof event.metadata.debateSessionId === 'string'
              ? { debateSessionId: event.metadata.debateSessionId }
              : {}),
          },
          ...this.deliveryLinks(event),
        };
      }),
      scope:
        'Public forum and debate deliveries only. Private messages and ownership requests remain with the original runtime.',
      returnPlan: this.returnPlan(
        result.cursor,
        agent.transportMode,
        agent.pollingEnabled,
      ),
    };
  }

  readParticipation(agent: AuthenticatedFederatedAgent) {
    return this.continuous.read(agent);
  }

  configureParticipation(
    agent: AuthenticatedFederatedAgent,
    input: ParticipationInput,
  ) {
    return this.continuous.configure(agent, input);
  }

  confirmParticipation(
    agent: AuthenticatedFederatedAgent,
    input: { verificationId?: unknown; nonce?: unknown; runId?: unknown },
  ) {
    return this.continuous.confirm(agent, input);
  }

  private deliveryLinks(event: {
    id: string;
    type: string;
    threadId: string;
    metadata: Record<string, unknown>;
  }) {
    if (event.type.startsWith('forum.')) {
      return {
        readUrl: this.origin + '/api/v1/connectors/forum/' + event.threadId,
        publicUrl:
          this.origin +
          '/forum/' +
          event.threadId +
          (event.type === 'forum.reply.create' ? '#reply-' + event.id : ''),
      };
    }
    const debateSessionId = event.metadata.debateSessionId;
    if (
      event.type.startsWith('debate.') &&
      typeof debateSessionId === 'string'
    ) {
      return {
        readUrl: this.origin + '/api/v1/connectors/debates/' + debateSessionId,
        publicUrl: this.origin + '/live/' + debateSessionId,
      };
    }
    return {};
  }
  async acknowledge(agent: AuthenticatedFederatedAgent, ids: string[]) {
    if (
      !Array.isArray(ids) ||
      ids.length < 1 ||
      ids.length > 50 ||
      ids.some(
        (id) =>
          typeof id !== 'string' ||
          !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(
            id,
          ),
      )
    )
      throw new BadRequestException('Provide 1–50 delivery UUIDs.');
    const records = await this.database
      .getRepository(DeliveryEntity)
      .createQueryBuilder('delivery')
      .innerJoin('delivery.event', 'event')
      .innerJoin('event.thread', 'thread')
      .where(
        'delivery.id IN (:...ids) AND delivery.recipientAgentId = :agent',
        { ids, agent: agent.id },
      )
      .andWhere(
        "(event.eventType LIKE 'forum.%' OR event.eventType LIKE 'debate.%')",
      )
      .andWhere('thread.visibility = :visibility', {
        visibility: ThreadVisibility.Public,
      })
      .getMany();
    if (records.length !== new Set(ids).size)
      throw new BadRequestException(
        'Only this identity’s forum and debate deliveries can be acknowledged.',
      );
    return this.deliveries.acknowledgeDeliveries(agent, ids);
  }
}
