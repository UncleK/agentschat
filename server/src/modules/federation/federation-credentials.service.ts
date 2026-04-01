import { Inject, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import {
  createHash,
  createHmac,
  randomBytes,
  timingSafeEqual,
} from 'node:crypto';
import { Repository } from 'typeorm';
import {
  APP_ENVIRONMENT,
  type AppEnvironment,
} from '../../config/environment';
import { AgentConnectionEntity } from '../../database/entities/agent-connection.entity';
import { AgentEntity } from '../../database/entities/agent.entity';
import { FederationHttpException } from './federation.errors';
import { AuthenticatedFederatedAgent } from './federation.types';

interface ClaimTokenPayload {
  kind: 'agent_claim';
  agentId: string;
  exp: number;
}

@Injectable()
export class FederationCredentialsService {
  constructor(
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
    @InjectRepository(AgentEntity)
    private readonly agentRepository: Repository<AgentEntity>,
    @InjectRepository(AgentConnectionEntity)
    private readonly agentConnectionRepository: Repository<AgentConnectionEntity>,
  ) {}

  createAgentClaimToken(agentId: string, ttlMs = 60 * 60 * 1000): string {
    const payload: ClaimTokenPayload = {
      kind: 'agent_claim',
      agentId,
      exp: Date.now() + ttlMs,
    };

    const encodedPayload = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const signature = this.signValue(encodedPayload, 'claim');

    return `claim.v1.${encodedPayload}.${signature}`;
  }

  verifyAgentClaimToken(token: string): ClaimTokenPayload {
    const [kind, version, encodedPayload, signature] = token.split('.');

    if (kind !== 'claim' || version !== 'v1' || !encodedPayload || !signature) {
      throw new FederationHttpException(
        401,
        'invalid_claim_token',
        'The claim token is malformed.',
      );
    }

    const expectedSignature = this.signValue(encodedPayload, 'claim');

    if (
      expectedSignature.length !== signature.length ||
      !timingSafeEqual(
        Buffer.from(expectedSignature, 'utf8'),
        Buffer.from(signature, 'utf8'),
      )
    ) {
      throw new FederationHttpException(
        401,
        'invalid_claim_token',
        'The claim token signature is invalid.',
      );
    }

    const payload = JSON.parse(
      Buffer.from(encodedPayload, 'base64url').toString('utf8'),
    ) as ClaimTokenPayload;

    if (payload.kind !== 'agent_claim' || !payload.agentId || payload.exp <= Date.now()) {
      throw new FederationHttpException(
        401,
        'expired_claim_token',
        'The claim token is expired or invalid.',
      );
    }

    return payload;
  }

  generateAgentAccessToken(connectionId: string): string {
    return `fed_v1.${connectionId}.${randomBytes(24).toString('hex')}`;
  }

  generateWebhookSecret(): string {
    return randomBytes(24).toString('hex');
  }

  hashValue(value: string): string {
    return createHash('sha256').update(value).digest('hex');
  }

  async authenticateAgentToken(token: string): Promise<AuthenticatedFederatedAgent> {
    const [version, connectionId] = token.split('.');

    if (version !== 'fed_v1' || !connectionId) {
      throw new FederationHttpException(
        401,
        'invalid_agent_token',
        'The agent bearer token is malformed.',
      );
    }

    const connection = await this.agentConnectionRepository.findOne({
      where: { id: connectionId },
      relations: { agent: true },
    });

    if (!connection?.agent) {
      throw new FederationHttpException(
        401,
        'invalid_agent_token',
        'The agent bearer token is invalid.',
      );
    }

    const actualHash = this.hashValue(token);

    if (
      actualHash.length !== connection.tokenHash.length ||
      !timingSafeEqual(
        Buffer.from(actualHash, 'utf8'),
        Buffer.from(connection.tokenHash, 'utf8'),
      )
    ) {
      throw new FederationHttpException(
        401,
        'invalid_agent_token',
        'The agent bearer token is invalid.',
      );
    }

    return {
      id: connection.agent.id,
      handle: connection.agent.handle,
      connectionId: connection.id,
      transportMode: connection.transportMode,
      pollingEnabled: connection.pollingEnabled,
    };
  }

  signWebhookPayload(secret: string, timestamp: string, body: string): string {
    return `sha256=${createHmac('sha256', secret)
      .update(`${timestamp}.${body}`)
      .digest('hex')}`;
  }

  async assertAgentExists(agentId: string): Promise<AgentEntity> {
    const agent = await this.agentRepository.findOneBy({ id: agentId });

    if (!agent) {
      throw new FederationHttpException(404, 'agent_not_found', `Agent ${agentId} was not found.`);
    }

    return agent;
  }

  private signValue(value: string, scope: string): string {
    return createHmac('sha256', `${this.environment.auth.jwtSecret}:${scope}`)
      .update(value)
      .digest('hex');
  }
}
