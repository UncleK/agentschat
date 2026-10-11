import {
  Injectable,
  ForbiddenException,
  ConflictException,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { randomBytes, randomUUID, createHash } from 'node:crypto';
import { DataSource, EntityManager } from 'typeorm';
import { inTransaction } from '../../database/transaction-context';
import { ClaimRequestEntity } from '../../database/entities/claim-request.entity';
import { UserEntity } from '../../database/entities/user.entity';
import { AgentEntity } from '../../database/entities/agent.entity';
import {
  ClaimRequestStatus,
  AgentOwnerType,
  EventActorType,
} from '../../database/domain.enums';
import { AuditLogEntity } from '../../database/entities/audit-log.entity';
import { FederationCredentialsService } from '../federation/federation-credentials.service';
import { AuthenticatedHuman } from '../auth/auth.types';
import { AgentsService } from './agents.service';

export interface BindingAuthorization {
  purpose?: string;
  accountId?: string;
  agentId?: string;
  requestId?: string;
  approved?: boolean;
}
interface Device {
  id: string;
  user_code: string;
  secret_hash: string;
  control_hash: string;
  agent_id: string;
  account_id: string;
  request_id: string;
  purpose: string;
  status: string;
  expires_at: Date;
  session_version: number | null;
  session_expires_at: Date | null;
}
const hash = (value: string) =>
  createHash('sha256').update(value).digest('hex');

@Injectable()
export class BindingDeviceService {
  constructor(
    private readonly db: DataSource,
    private readonly credentials: FederationCredentialsService,
    private readonly agents: AgentsService,
  ) {}

  async invitationPreview(token: string, requestId: string, challenge: string) {
    if (typeof challenge !== 'string' || !challenge.trim())
      throw new BadRequestException('A binding challenge is required.');
    const control = await this.credentials.authenticateAgentToken(token);
    return inTransaction(this.db, async (m) => {
      const agent = await m.getRepository(AgentEntity).findOne({
        where: { id: control.id },
        lock: { mode: 'pessimistic_write' },
      });
      if (!agent) throw new NotFoundException('Agent not found.');
      const claim = await m.getRepository(ClaimRequestEntity).findOne({
        where: { id: requestId },
        lock: { mode: 'pessimistic_write' },
      });
      if (
        !claim ||
        claim.challengeTokenHash !== hash(challenge.trim()) ||
        (claim.agentId && claim.agentId !== control.id)
      )
        throw new ForbiddenException(
          'Binding request does not match this controller.',
        );
      if (
        claim.status !== ClaimRequestStatus.Confirmed &&
        (claim.status !== ClaimRequestStatus.Pending ||
          claim.expiresAt.getTime() <= Date.now())
      )
        throw new ConflictException('Binding request expired or consumed.');
      if (
        agent.ownerType === AgentOwnerType.Human &&
        agent.ownerUserId !== claim.requestedByUserId
      )
        throw new ConflictException(
          'This Agent already belongs to another account.',
        );
      const bound =
        agent.ownerType === AgentOwnerType.Human &&
        agent.ownerUserId === claim.requestedByUserId;
      if (claim.status === ClaimRequestStatus.Confirmed && !bound)
        throw new ConflictException(
          'The current ownership no longer matches this invitation.',
        );
      if (bound && claim.status === ClaimRequestStatus.Pending) {
        // A new invitation to an already-owned Agent grants no new ownership.
        await m.getRepository(ClaimRequestEntity).update(claim.id, {
          agentId: agent.id,
          status: ClaimRequestStatus.Confirmed,
          confirmedAt: new Date(),
        });
      }
      const account = await m
        .getRepository(UserEntity)
        .findOneByOrFail({ id: claim.requestedByUserId });
      return {
        status: bound ? 'bound' : 'ready',
        requestId,
        accountId: account.id,
        accountName: account.displayName,
        agentId: agent.id,
        handle: agent.handle,
        displayName: agent.displayName,
        expiresAt: claim.expiresAt.toISOString(),
      };
    });
  }

  async invitationStatus(human: AuthenticatedHuman, requestId: string) {
    const claim = await this.db.getRepository(ClaimRequestEntity).findOne({
      where: { id: requestId },
      relations: { agent: true },
    });
    if (!claim) throw new NotFoundException('Binding invitation not found.');
    if (claim.requestedByUserId !== human.id)
      throw new ForbiddenException(
        'This invitation belongs to another account.',
      );
    if (claim.status === ClaimRequestStatus.Confirmed) {
      const agent = claim.agent;
      const bound =
        agent?.ownerType === AgentOwnerType.Human &&
        agent.ownerUserId === human.id;
      return {
        status: bound ? 'bound' : 'ownership_changed',
        requestId,
        agent: bound
          ? {
              id: agent.id,
              handle: agent.handle,
              displayName: agent.displayName,
            }
          : null,
      };
    }
    if (
      claim.expiresAt.getTime() <= Date.now() ||
      claim.status !== ClaimRequestStatus.Pending
    )
      return {
        status:
          claim.status === ClaimRequestStatus.Rejected
            ? 'cancelled'
            : 'expired',
        requestId,
        agent: null,
      };
    const [device] = await this.db.query<
      Array<{ status: string; user_code: string }>
    >(
      "SELECT status,user_code FROM binding_devices WHERE request_id=$1 AND account_id=$2 AND status<>'consumed' AND expires_at>now() ORDER BY created_at DESC LIMIT 1",
      [requestId, human.id],
    );
    return {
      status: device
        ? device.status === 'approved'
          ? 'awaiting_controller'
          : 'awaiting_browser'
        : 'pending',
      requestId,
      agent: null,
      verificationPath: device
        ? `/binding/authorize?code=${device.user_code}`
        : null,
    };
  }

  async start(controlToken: string, requestId: string, challenge: string) {
    if (
      typeof requestId !== 'string' ||
      !/^[0-9a-f-]{36}$/i.test(requestId) ||
      typeof challenge !== 'string'
    )
      throw new BadRequestException(
        'A binding request and challenge are required.',
      );
    const control = await this.credentials.authenticateAgentToken(controlToken);
    const claim = await this.db
      .getRepository(ClaimRequestEntity)
      .findOneBy({ id: requestId });
    if (
      !claim ||
      claim.challengeTokenHash !== hash(challenge.trim()) ||
      (claim.agentId && claim.agentId !== control.id)
    )
      throw new ForbiddenException(
        'Binding request does not match this controller.',
      );
    if (
      claim.status !== ClaimRequestStatus.Pending ||
      claim.expiresAt.getTime() <= Date.now()
    )
      throw new ConflictException('Binding request expired or consumed.');
    const id = randomUUID(),
      deviceSecret = randomBytes(32).toString('hex'),
      userCode = randomBytes(12).toString('hex');
    const expiresAt = new Date(
      Math.min(Date.now() + 10 * 60 * 1000, claim.expiresAt.getTime()),
    );
    await inTransaction(this.db, async (m) => {
      await m.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [
        `binding-device:${control.id}`,
      ]);
      const [count] = await m.query<Array<{ count: string }>>(
        "SELECT count(*) FROM binding_devices WHERE agent_id=$1 AND status<>'consumed' AND expires_at>now()",
        [control.id],
      );
      if (Number(count.count) >= 20)
        throw new ConflictException('Too many pending device authorizations.');
      await m.query(
        `INSERT INTO binding_devices(id,user_code,secret_hash,control_hash,agent_id,account_id,request_id,purpose,expires_at) VALUES($1,$2,$3,$4,$5,$6,$7,'bind_account',$8)`,
        [
          id,
          userCode,
          hash(deviceSecret),
          hash(controlToken),
          control.id,
          claim.requestedByUserId,
          requestId,
          expiresAt,
        ],
      );
    });
    return {
      id,
      deviceSecret,
      userCode,
      expiresAt: expiresAt.toISOString(),
      verificationPath: `/binding/authorize?code=${userCode}`,
    };
  }
  private async read(
    m: EntityManager,
    key: string,
    byCode = false,
    lock = false,
  ): Promise<Device> {
    const [d] = await m.query<Device[]>(
      `SELECT * FROM binding_devices WHERE ${byCode ? 'user_code' : 'id'}=$1${lock ? ' FOR UPDATE' : ''}`,
      [key],
    );
    if (!d) throw new NotFoundException('Authorization not found.');
    if (d.status === 'consumed' || d.expires_at.getTime() <= Date.now())
      throw new ConflictException('Authorization expired or consumed.');
    return d;
  }
  private scope(d: Device, a: BindingAuthorization) {
    if (
      !a ||
      a.purpose !== d.purpose ||
      a.accountId !== d.account_id ||
      a.agentId !== d.agent_id ||
      a.requestId !== d.request_id ||
      a.approved !== true
    )
      throw new ForbiddenException(
        'Explicit authorization scope does not match.',
      );
  }
  private async preview(d: Device) {
    const account = await this.db
      .getRepository(UserEntity)
      .findOneByOrFail({ id: d.account_id });
    const agent = await this.db
      .getRepository(AgentEntity)
      .findOneByOrFail({ id: d.agent_id });
    return {
      purpose: d.purpose,
      accountId: d.account_id,
      accountName: account.displayName,
      accountUsername: account.username,
      agentId: d.agent_id,
      agentName: agent.displayName,
      requestId: d.request_id,
      expiresAt: d.expires_at.toISOString(),
      status: d.status,
    };
  }
  async browserPreview(human: AuthenticatedHuman, code: string) {
    const d = await this.read(this.db.manager, code, true);
    if (human.id !== d.account_id)
      throw new ForbiddenException(
        'Sign in to the account that requested this binding.',
      );
    return this.preview(d);
  }
  async approve(
    human: AuthenticatedHuman,
    code: string,
    authorization: BindingAuthorization,
  ) {
    return inTransaction(this.db, async (m) => {
      const d = await this.read(m, code, true, true);
      if (human.id !== d.account_id || !human.authenticatedSession)
        throw new ForbiddenException('Wrong account.');
      this.scope(d, authorization);
      if (d.status !== 'pending')
        throw new ConflictException('Browser approval already recorded.');
      await m.query(
        "UPDATE binding_devices SET status='approved',session_version=$2,session_expires_at=$3,approved_at=now() WHERE id=$1",
        [
          d.id,
          human.authenticatedSession.version,
          new Date(human.authenticatedSession.expiresAt),
        ],
      );
      const audits = m.getRepository(AuditLogEntity);
      await audits.save(
        audits.create({
          actorType: EventActorType.Human,
          actorUserId: human.id,
          action: 'agent.binding.browser_approved',
          entityType: 'agent',
          entityId: d.agent_id,
          payload: {
            purpose: d.purpose,
            requestId: d.request_id,
            deviceId: d.id,
          },
        }),
      );
      return {
        status: 'approved',
        message:
          'Return to the original controller terminal to approve the binding.',
      };
    });
  }
  private async assertController(d: Device, token: string, secret: string) {
    const c = await this.credentials.authenticateAgentToken(token);
    if (
      c.id !== d.agent_id ||
      typeof secret !== 'string' ||
      hash(secret) !== d.secret_hash ||
      hash(token) !== d.control_hash
    )
      throw new ForbiddenException(
        'Wrong original controller or device proof.',
      );
  }
  async poll(token: string, id: string, secret: string) {
    const d = await this.read(this.db.manager, id);
    await this.assertController(d, token, secret);
    return this.preview(d);
  }
  async confirm(
    token: string,
    id: string,
    secret: string,
    challenge: string,
    authorization: BindingAuthorization,
  ) {
    return inTransaction(this.db, async (m) => {
      const d = await this.read(m, id, false, true);
      await this.assertController(d, token, secret);
      this.scope(d, authorization);
      if (
        d.status !== 'approved' ||
        d.session_version === null ||
        !d.session_expires_at
      )
        throw new ForbiddenException('Browser approval is required first.');
      const account = await m
        .getRepository(UserEntity)
        .findOneByOrFail({ id: d.account_id });
      const human: AuthenticatedHuman = {
        id: account.id,
        email: account.email,
        username: account.username,
        displayName: account.displayName,
        avatarUrl: account.avatarUrl,
        authProvider: account.authProvider,
        emailVerified: account.emailVerifiedAt !== null,
        authenticatedSession: {
          version: d.session_version,
          expiresAt: d.session_expires_at.getTime(),
        },
      };
      const result = await this.agents.confirmClaim(
        human,
        d.agent_id,
        d.request_id,
        challenge,
        token,
        authorization,
      );
      await m.query(
        "UPDATE binding_devices SET status='consumed',consumed_at=now() WHERE id=$1",
        [d.id],
      );
      return result;
    });
  }
}
