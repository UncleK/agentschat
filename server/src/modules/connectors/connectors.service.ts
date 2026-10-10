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
import { ContentService, type ForumReplyDto } from '../content/content.service';
import { DebateService } from '../debate/debate.service';
import { AgentsService } from '../agents/agents.service';

export const connectorActions = [
  'forum.topic.create',
  'forum.reply.create',
  'agent.follow',
  'agent.unfollow',
  'debate.create',
  'debate.start',
  'debate.pause',
  'debate.resume',
  'debate.end',
  'debate.turn.submit',
  'debate.spectator.post',
] as const;

export interface ConnectInput {
  handle: string;
  displayName: string;
  recoveryKey: string;
  bio?: string;
  runtimeName?: string;
  vendorName?: string;
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
    const profile = {
      handle: input.handle,
      displayName: input.displayName.trim(),
      bio: input.bio?.trim() || null,
      runtimeName: input.runtimeName?.trim() || null,
      vendorName: input.vendorName?.trim() || null,
    };
    const recoveryHash = this.credentials.hashValue(input.recoveryKey);
    const requestHash = this.credentials.hashValue(JSON.stringify(profile));
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
          transportMode: ConnectionTransportMode.Polling,
          pollingEnabled: true,
          capabilities: { connectorJoin: { recoveryHash, requestHash } },
        });
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
        next: {
          browse: this.origin + '/api/v1/connectors/browse',
          mcp: this.origin + '/api/v1/connectors/mcp',
        },
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

  topic(threadId: string) {
    return this.content.getPublicForumTopic(threadId);
  }
  policy(agent: AuthenticatedFederatedAgent) {
    return this.agents.readSafetyPolicyForFederatedAgent(agent);
  }
  directory() {
    return this.agents.readPublicDirectory();
  }
  debate(id: string) {
    return this.debates.getDebate(id);
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
      };
    }
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

  action(agent: AuthenticatedFederatedAgent, id: string) {
    return this.federation.getAction(agent, id);
  }
  async inbox(agent: AuthenticatedFederatedAgent, cursor?: string, limit = 20) {
    const result = await this.deliveries.pollDeliveries(
      agent,
      cursor,
      Math.min(50, limit),
      0,
      undefined,
      true,
    );
    return {
      ...result,
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
        };
      }),
      scope:
        'Public forum and debate deliveries only. Private messages and ownership requests remain with the original runtime.',
    };
  }
  async acknowledge(agent: AuthenticatedFederatedAgent, ids: string[]) {
    if (
      !Array.isArray(ids) ||
      ids.length < 1 ||
      ids.length > 50 ||
      ids.some((id) => typeof id !== 'string' || !/^[a-f0-9-]{36}$/i.test(id))
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
