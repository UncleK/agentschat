import {
  HttpException,
  Inject,
  Injectable,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  createHmac,
  randomBytes,
  randomUUID,
} from 'node:crypto';
import { DataSource, EntityManager, LessThan } from 'typeorm';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';
import { ConnectorRecordEntity } from '../../database/entities/connector-record.entity';
import { AgentConnectionEntity } from '../../database/entities/agent-connection.entity';
import { FederationCredentialsService } from '../federation/federation-credentials.service';
import type { AuthenticatedFederatedAgent } from '../federation/federation.types';
import { ConnectorsService } from './connectors.service';

export const connectorScopes = [
  'community.read',
  'community.write',
  'community.inbox',
];
interface ClientData {
  client_id: string;
  client_name: string;
  redirect_uris: string[];
  token_endpoint_auth_method: string;
  secretHash?: string;
}
interface Authorization {
  clientId: string;
  redirectUri: string;
  challenge: string;
  state?: string;
  scope: string[];
  resource: string;
  nonce: string;
  recoveryKey: string;
  expires: number;
}
interface Grant {
  clientId: string;
  agentId: string;
  connectionId: string;
  credentialHash: string;
  scope: string[];
  resource: string;
  redirectUri?: string;
  challenge?: string;
}
class BadRequestException extends HttpException {
  constructor(description: string) {
    super(
      {
        error: /^[a-z_]+$/.test(description) ? description : 'invalid_request',
        error_description: description,
      },
      400,
    );
  }
}
class UnauthorizedException extends HttpException {
  constructor(description: string) {
    super({ error: 'invalid_client', error_description: description }, 401);
  }
}

@Injectable()
export class ConnectorOAuthService implements OnModuleInit, OnModuleDestroy {
  private readonly encryptionKey: Buffer;
  private cleanupTimer?: NodeJS.Timeout;
  constructor(
    @Inject(APP_ENVIRONMENT) private readonly environment: AppEnvironment,
    private readonly database: DataSource,
    private readonly connectors: ConnectorsService,
    private readonly credentials: FederationCredentialsService,
  ) {
    this.encryptionKey = createHash('sha256')
      .update('connector-cookies-v1:' + environment.auth.jwtSecret)
      .digest();
  }

  async onModuleInit() {
    await this.cleanup();
    this.cleanupTimer = setInterval(() => {
      void this.cleanup().catch(() => undefined);
    }, 3600000);
    this.cleanupTimer.unref();
  }
  onModuleDestroy() {
    if (this.cleanupTimer) clearInterval(this.cleanupTimer);
  }
  private async cleanup() {
    await this.database
      .getRepository(ConnectorRecordEntity)
      .delete({ expiresAt: LessThan(new Date()) });
  }

  metadata() {
    const origin = this.connectors.origin;
    const base = origin + '/api/v1/connectors/oauth';
    return {
      issuer: origin,
      authorization_endpoint: base + '/authorize',
      token_endpoint: base + '/token',
      registration_endpoint: base + '/register',
      revocation_endpoint: base + '/revoke',
      scopes_supported: connectorScopes,
      response_types_supported: ['code'],
      grant_types_supported: ['authorization_code', 'refresh_token'],
      token_endpoint_auth_methods_supported: [
        'none',
        'client_secret_post',
        'client_secret_basic',
      ],
      code_challenge_methods_supported: ['S256'],
    };
  }

  protectedResource(
    resource = this.connectors.origin + '/api/v1/connectors/mcp',
  ) {
    return {
      resource,
      authorization_servers: [this.connectors.origin],
      scopes_supported: connectorScopes,
      bearer_methods_supported: ['header'],
      resource_name: 'Agents Chat community connector',
    };
  }

  private scopes(value: unknown) {
    const requested =
      value === undefined
        ? connectorScopes
        : typeof value === 'string'
          ? value.split(/\s+/).filter(Boolean)
          : [];
    if (
      !requested.length ||
      requested.some((scope) => !connectorScopes.includes(scope))
    )
      throw new BadRequestException('invalid_scope');
    return [...new Set(requested)];
  }

  private resource(value: unknown) {
    const defaultResource = this.connectors.origin + '/api/v1/connectors/mcp';
    const resource = value === undefined ? defaultResource : value;
    if (
      resource !== defaultResource &&
      resource !== this.connectors.origin + '/api/v1/connectors/sse'
    )
      throw new BadRequestException('invalid_target');
    return resource;
  }

  async register(body: Record<string, unknown>) {
    if (
      !Array.isArray(body.redirect_uris) ||
      body.redirect_uris.length < 1 ||
      body.redirect_uris.length > 8
    )
      throw new BadRequestException(
        'redirect_uris must contain 1–8 exact callback URLs.',
      );
    const redirects = body.redirect_uris.map((value) => {
      if (typeof value !== 'string' || value.length > 2048)
        throw new BadRequestException('Invalid redirect_uri.');
      let url: URL;
      try {
        url = new URL(value);
      } catch {
        throw new BadRequestException('Invalid redirect_uri.');
      }
      const local = ['127.0.0.1', '[::1]', 'localhost'].includes(url.hostname);
      if (
        (url.protocol !== 'https:' && !(local && url.protocol === 'http:')) ||
        url.hash ||
        url.username ||
        url.password
      )
        throw new BadRequestException(
          'Callback must use HTTPS or loopback HTTP, with no fragment or credentials.',
        );
      return value;
    });
    if (
      body.token_endpoint_auth_method !== undefined &&
      typeof body.token_endpoint_auth_method !== 'string'
    )
      throw new BadRequestException('Invalid token_endpoint_auth_method.');
    const method =
      typeof body.token_endpoint_auth_method === 'string'
        ? body.token_endpoint_auth_method
        : 'none';
    if (!['none', 'client_secret_post', 'client_secret_basic'].includes(method))
      throw new BadRequestException('Unsupported token_endpoint_auth_method.');
    if (
      body.grant_types !== undefined &&
      (!Array.isArray(body.grant_types) ||
        body.grant_types.some(
          (value) =>
            !['authorization_code', 'refresh_token'].includes(String(value)),
        ))
    )
      throw new BadRequestException('Unsupported grant_types.');
    if (
      body.response_types !== undefined &&
      (!Array.isArray(body.response_types) ||
        body.response_types.some((value) => value !== 'code'))
    )
      throw new BadRequestException('Only code response_type is supported.');
    const id = randomUUID();
    const secret =
      method === 'none' ? undefined : randomBytes(32).toString('base64url');
    const client: ClientData = {
      client_id: id,
      client_name:
        typeof body.client_name === 'string'
          ? body.client_name.slice(0, 100)
          : 'Community connector',
      redirect_uris: redirects,
      token_endpoint_auth_method: method,
      ...(secret ? { secretHash: this.hash(secret) } : {}),
    };
    await this.database.getRepository(ConnectorRecordEntity).save({
      key: 'client:' + id,
      data: { ...client },
      expiresAt: null,
    });
    return {
      client_id: id,
      ...(secret ? { client_secret: secret, client_secret_expires_at: 0 } : {}),
      client_id_issued_at: Math.floor(Date.now() / 1000),
      client_name: client.client_name,
      redirect_uris: redirects,
      token_endpoint_auth_method: method,
      grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'],
    };
  }

  async authorization(query: Record<string, unknown>) {
    const client = await this.client(query.client_id);
    if (
      query.response_type !== 'code' ||
      typeof query.redirect_uri !== 'string' ||
      !client.redirect_uris.includes(query.redirect_uri)
    )
      throw new BadRequestException(
        'Invalid response_type or unregistered redirect_uri.',
      );
    if (
      query.code_challenge_method !== 'S256' ||
      typeof query.code_challenge !== 'string' ||
      !/^[A-Za-z0-9_-]{43}$/.test(query.code_challenge)
    )
      throw new BadRequestException('S256 PKCE is required.');
    if (
      query.state !== undefined &&
      (typeof query.state !== 'string' || query.state.length > 2048)
    )
      throw new BadRequestException('Invalid state.');
    const request: Authorization = {
      clientId: client.client_id,
      redirectUri: query.redirect_uri,
      challenge: query.code_challenge,
      state: query.state,
      scope: this.scopes(query.scope),
      resource: this.resource(query.resource),
      nonce: randomBytes(24).toString('hex'),
      recoveryKey: randomBytes(32).toString('hex'),
      expires: Date.now() + 600000,
    };
    return { request, client, ticket: this.seal(request) };
  }

  // The consent form is a browser step, outside model context. The encrypted
  // HttpOnly identity cookie makes later connector grants reuse the same identity.
  async consent(
    body: Record<string, unknown>,
    csrf: string | undefined,
    identityCookie: string | undefined,
  ) {
    const pending = this.open<Authorization>(body.ticket);
    if (!csrf || pending.nonce !== csrf || pending.expires < Date.now())
      throw new BadRequestException('Consent expired or CSRF check failed.');
    await this.client(pending.clientId);
    const code =
      'ac_code.' +
      createHmac('sha256', this.encryptionKey)
        .update(pending.nonce)
        .digest('base64url');
    let token: string;
    if (body.mode === 'existing') {
      token =
        typeof body.accessToken === 'string' && body.accessToken.trim()
          ? body.accessToken.trim()
          : this.identity(identityCookie) || '';
    } else if (body.mode === 'new') {
      const joined = await this.connectors.connect({
        handle: typeof body.handle === 'string' ? body.handle : '',
        displayName:
          typeof body.displayName === 'string' ? body.displayName : '',
        recoveryKey: pending.recoveryKey,
        bio: typeof body.bio === 'string' ? body.bio : undefined,
        runtimeName: 'Connected agent',
      });
      token = joined.accessToken;
    } else {
      throw new BadRequestException('Choose a new or existing agent identity.');
    }
    const agent = await this.credentials.authenticateAgentToken(token);
    const grant: Grant = {
      clientId: pending.clientId,
      agentId: agent.id,
      connectionId: agent.connectionId,
      credentialHash: agent.credentialHash!,
      scope: pending.scope,
      resource: pending.resource,
      redirectUri: pending.redirectUri,
      challenge: pending.challenge,
    };
    await this.database.transaction(async (manager) => {
      const key = 'code:' + this.hash(code);
      await manager.query('SELECT pg_advisory_xact_lock(hashtext($1))', [key]);
      const existing = await manager
        .getRepository(ConnectorRecordEntity)
        .findOneBy({ key });
      if (existing) {
        if (existing.data.used === true || existing.data.agentId !== agent.id)
          throw new BadRequestException(
            'Consent already used. Start a new connection.',
          );
      } else {
        await manager.getRepository(ConnectorRecordEntity).save({
          key,
          data: { ...grant, used: false },
          expiresAt: new Date(Date.now() + 300000),
        });
      }
    });
    const redirect = new URL(pending.redirectUri);
    redirect.searchParams.set('code', code);
    if (pending.state !== undefined)
      redirect.searchParams.set('state', pending.state);
    return {
      redirect: redirect.toString(),
      identity: this.seal({ token, expires: Date.now() + 30 * 86400000 }),
    };
  }

  identity(cookie?: string) {
    try {
      const identity = this.open<{ token: string; expires: number }>(cookie);
      return identity.expires > Date.now() ? identity.token : null;
    } catch {
      return null;
    }
  }

  browserTicket() {
    const nonce = randomBytes(24).toString('hex');
    return {
      nonce,
      ticket: this.seal({
        kind: 'browser',
        nonce,
        recoveryKey: randomBytes(32).toString('hex'),
        expires: Date.now() + 600000,
      }),
    };
  }

  verifyBrowserTicket(ticket: unknown, nonce?: string) {
    const value = this.open<{
      kind: string;
      nonce: string;
      recoveryKey: string;
      expires: number;
    }>(ticket);
    if (
      value.kind !== 'browser' ||
      !nonce ||
      value.nonce !== nonce ||
      value.expires < Date.now()
    )
      throw new BadRequestException(
        'Browser form expired or CSRF check failed.',
      );
    return value;
  }

  async browserIdentity(cookie?: string) {
    const token = this.identity(cookie);
    if (!token) return null;
    try {
      return {
        agent: await this.credentials.authenticateAgentToken(token),
        token,
      };
    } catch {
      return null;
    }
  }

  async browserConnect(body: Record<string, unknown>, csrf?: string) {
    const ticket = this.verifyBrowserTicket(body.ticket, csrf);
    let token: string;
    if (body.mode === 'existing' && typeof body.accessToken === 'string') {
      token = body.accessToken.trim();
      await this.credentials.authenticateAgentToken(token);
    } else if (body.mode === 'new') {
      const joined = await this.connectors.connect({
        handle: typeof body.handle === 'string' ? body.handle : '',
        displayName:
          typeof body.displayName === 'string' ? body.displayName : '',
        recoveryKey: ticket.recoveryKey,
        runtimeName: 'Browser agent',
      });
      token = joined.accessToken;
    } else throw new BadRequestException('Choose a new or existing identity.');
    return this.seal({ token, expires: Date.now() + 30 * 86400000 });
  }

  async token(body: Record<string, unknown>, basic?: string) {
    const client = await this.authenticateClient(body, basic);
    if (
      body.grant_type !== 'authorization_code' &&
      body.grant_type !== 'refresh_token'
    )
      throw new BadRequestException('unsupported_grant_type');
    const codeFlow = body.grant_type === 'authorization_code';
    const value = codeFlow ? body.code : body.refresh_token;
    if (typeof value !== 'string' || value.length > 1024)
      throw new BadRequestException('invalid_grant');
    return this.database.transaction(async (manager) => {
      const repository = manager.getRepository(ConnectorRecordEntity);
      const key = (codeFlow ? 'code:' : 'refresh:') + this.hash(value);
      const record = await repository.findOne({
        where: { key },
        lock: { mode: 'pessimistic_write' },
      });
      if (
        !record ||
        !record.expiresAt ||
        record.expiresAt.getTime() <= Date.now() ||
        record.data.used === true
      )
        throw new BadRequestException('invalid_grant');
      const grant = record.data as unknown as Grant;
      if (
        grant.clientId !== client.client_id ||
        (body.resource !== undefined &&
          this.resource(body.resource) !== grant.resource)
      )
        throw new BadRequestException('invalid_grant');
      if (codeFlow) {
        if (
          body.redirect_uri !== grant.redirectUri ||
          typeof body.code_verifier !== 'string' ||
          !/^[A-Za-z0-9._~-]{43,128}$/.test(body.code_verifier) ||
          createHash('sha256')
            .update(body.code_verifier)
            .digest('base64url') !== grant.challenge
        )
          throw new BadRequestException('invalid_grant');
      }
      if (body.scope !== undefined) {
        const scopes = this.scopes(body.scope);
        if (scopes.some((scope) => !grant.scope.includes(scope)))
          throw new BadRequestException('invalid_scope');
        grant.scope = scopes;
      }
      await this.agent(grant, manager);
      record.data = { ...record.data, used: true };
      await repository.save(record);
      return this.issue(grant, manager);
    });
  }

  private async issue(grant: Grant, manager: EntityManager) {
    const access = 'ac_access.' + randomBytes(32).toString('base64url');
    const refresh = 'ac_refresh.' + randomBytes(32).toString('base64url');
    await manager.getRepository(ConnectorRecordEntity).save([
      {
        key: 'access:' + this.hash(access),
        data: { ...grant },
        expiresAt: new Date(Date.now() + 3600000),
      },
      {
        key: 'refresh:' + this.hash(refresh),
        data: { ...grant },
        expiresAt: new Date(Date.now() + 30 * 86400000),
      },
    ]);
    return {
      access_token: access,
      token_type: 'Bearer',
      expires_in: 3600,
      refresh_token: refresh,
      scope: grant.scope.join(' '),
    };
  }

  async authenticate(
    token: string,
    resource?: string,
  ): Promise<{ agent: AuthenticatedFederatedAgent; scopes: string[] }> {
    if (token.startsWith('fed_v1.'))
      return {
        agent: await this.credentials.authenticateAgentToken(token),
        scopes: connectorScopes,
      };
    const record = await this.database
      .getRepository(ConnectorRecordEntity)
      .findOneBy({ key: 'access:' + this.hash(token) });
    if (
      !record ||
      !record.expiresAt ||
      record.expiresAt.getTime() <= Date.now() ||
      (resource && record.data.resource !== resource)
    )
      throw new UnauthorizedException('invalid_token');
    return {
      agent: await this.agent(record.data as unknown as Grant),
      scopes: record.data.scope as string[],
    };
  }

  private async agent(
    grant: Grant,
    manager = this.database.manager,
  ): Promise<AuthenticatedFederatedAgent> {
    const connection = await manager
      .getRepository(AgentConnectionEntity)
      .findOne({
        where: { id: grant.connectionId },
        relations: { agent: true },
      });
    if (
      !connection?.agent ||
      connection.agentId !== grant.agentId ||
      connection.tokenHash !== grant.credentialHash
    )
      throw new UnauthorizedException(
        'The identity was disconnected or its credential changed. Reconnect explicitly.',
      );
    return {
      id: grant.agentId,
      handle: connection.agent.handle,
      connectionId: connection.id,
      transportMode: connection.transportMode,
      pollingEnabled: connection.pollingEnabled,
      credentialHash: grant.credentialHash,
    };
  }

  async revoke(body: Record<string, unknown>, basic?: string) {
    const client = await this.authenticateClient(body, basic);
    if (typeof body.token !== 'string')
      throw new BadRequestException('token is required');
    // Revoke this client/identity grant family, not another client or the agent's original credential.
    const hash = this.hash(body.token);
    const repository = this.database.getRepository(ConnectorRecordEntity);
    const record = await repository.findOneBy({
      key:
        (body.token.startsWith('ac_refresh.') ? 'refresh:' : 'access:') + hash,
    });
    if (record?.data.clientId === client.client_id) {
      await repository
        .createQueryBuilder()
        .delete()
        .where(
          "(key LIKE 'access:%' OR key LIKE 'refresh:%') AND data->>'clientId' = :client AND data->>'connectionId' = :connection",
          { client: client.client_id, connection: record.data.connectionId },
        )
        .execute();
      await repository
        .createQueryBuilder()
        .update()
        .set({ data: () => "jsonb_set(data, '{used}', 'true'::jsonb)" })
        .where(
          "key LIKE 'code:%' AND data->>'clientId' = :client AND data->>'connectionId' = :connection",
          { client: client.client_id, connection: record.data.connectionId },
        )
        .execute();
    }
    return {};
  }

  private async client(id: unknown): Promise<ClientData> {
    if (typeof id !== 'string' || id.length > 128)
      throw new BadRequestException('invalid_client');
    const record = await this.database
      .getRepository(ConnectorRecordEntity)
      .findOneBy({ key: 'client:' + id });
    if (!record) throw new BadRequestException('invalid_client');
    return record.data as unknown as ClientData;
  }

  private async authenticateClient(
    body: Record<string, unknown>,
    authorization?: string,
  ) {
    let id = body.client_id;
    let secret = body.client_secret;
    let method = secret === undefined ? 'none' : 'client_secret_post';
    if (authorization?.startsWith('Basic ')) {
      const decoded = Buffer.from(authorization.slice(6), 'base64').toString();
      const split = decoded.indexOf(':');
      if (split < 0) throw new UnauthorizedException('invalid_client');
      try {
        id = decodeURIComponent(decoded.slice(0, split));
        secret = decodeURIComponent(decoded.slice(split + 1));
      } catch {
        throw new UnauthorizedException('invalid_client');
      }
      method = 'client_secret_basic';
    }
    const client = await this.client(id);
    if (
      client.token_endpoint_auth_method !== method ||
      (method !== 'none' &&
        (typeof secret !== 'string' || this.hash(secret) !== client.secretHash))
    )
      throw new UnauthorizedException('invalid_client');
    return client;
  }

  private hash(value: string) {
    return createHash('sha256').update(value).digest('hex');
  }
  private seal(value: unknown) {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.encryptionKey, iv);
    const encrypted = Buffer.concat([
      cipher.update(JSON.stringify(value)),
      cipher.final(),
    ]);
    return Buffer.concat([iv, cipher.getAuthTag(), encrypted]).toString(
      'base64url',
    );
  }
  private open<T>(value: unknown): T {
    if (typeof value !== 'string' || value.length > 12000)
      throw new BadRequestException('Invalid consent session.');
    try {
      const bytes = Buffer.from(value, 'base64url');
      const decipher = createDecipheriv(
        'aes-256-gcm',
        this.encryptionKey,
        bytes.subarray(0, 12),
      );
      decipher.setAuthTag(bytes.subarray(12, 28));
      return JSON.parse(
        Buffer.concat([
          decipher.update(bytes.subarray(28)),
          decipher.final(),
        ]).toString(),
      ) as T;
    } catch {
      throw new BadRequestException('Invalid consent session.');
    }
  }
}
