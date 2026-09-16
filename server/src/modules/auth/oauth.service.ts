import {
  BadRequestException,
  Inject,
  Injectable,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { createHash, randomBytes } from 'node:crypto';
import { DataSource, EntityManager } from 'typeorm';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';
import { UserEntity } from '../../database/entities/user.entity';
import { AuthProvider } from '../../database/domain.enums';
import { AuthService } from './auth.service';
import { type OAuthProvider } from './oauth.config';
import { type AuthenticatedHuman } from './auth.types';

const random = () => randomBytes(32).toString('base64url');
const hash = (value: string) =>
  createHash('sha256').update(value).digest('hex');
const challenge = (value: string) =>
  createHash('sha256').update(value).digest('base64url');
interface Identity {
  subject: string;
  email: string;
  name: string;
  avatar: string | null;
}
interface Flow {
  id: string;
  provider: OAuthProvider;
  client: 'web' | 'mobile';
  client_challenge: string;
  provider_verifier: string;
  link_user_id: string | null;
  link_token_version: number | null;
  identity: Identity;
  error_code: string | null;
}

@Injectable()
export class OAuthService {
  constructor(
    @Inject(APP_ENVIRONMENT) private readonly env: AppEnvironment,
    private readonly db: DataSource,
    private readonly auth: AuthService,
  ) {}

  providers() {
    return ['google', 'github'].map((id) => {
      const config = this.env.auth.oauth?.[id as OAuthProvider];
      return {
        id,
        enabled: Boolean(
          this.env.auth.oauth?.publicBaseUrl &&
          config?.clientId &&
          config.clientSecret,
        ),
      };
    });
  }
  async identities(human: AuthenticatedHuman) {
    return this.db.query<{ provider: string }[]>(
      'SELECT provider FROM auth_identities WHERE user_id=$1 ORDER BY provider',
      [human.id],
    );
  }
  private config(provider: string) {
    if (provider !== 'google' && provider !== 'github')
      throw new BadRequestException('Unknown sign-in provider.');
    const config = this.env.auth.oauth;
    if (
      !config?.publicBaseUrl ||
      !config[provider].clientId ||
      !config[provider].clientSecret
    )
      throw new ServiceUnavailableException(
        'This sign-in provider is not configured yet.',
      );
    return {
      ...config[provider],
      redirectUri: `${config.publicBaseUrl}/api/oauth/callback/${provider}`,
    };
  }
  async start(
    provider: string,
    input: { codeChallenge?: string; client?: string },
    human?: AuthenticatedHuman,
  ) {
    const config = this.config(provider);
    if (
      !/^[A-Za-z0-9_-]{43}$/.test(input?.codeChallenge ?? '') ||
      !['web', 'mobile'].includes(input?.client ?? '')
    )
      throw new BadRequestException(
        'A valid client and S256 challenge are required.',
      );
    const id = random(),
      state = random(),
      verifier = random();
    const user = human
      ? await this.db.getRepository(UserEntity).findOneBy({ id: human.id })
      : null;
    if (human && !user) throw new UnauthorizedException();
    await this.db.query(
      'DELETE FROM auth_oauth_flows WHERE expires_at < now()',
    );
    await this.db.query(
      `INSERT INTO auth_oauth_flows
      (id,provider,client,state_hash,client_challenge,provider_verifier,link_user_id,link_token_version,expires_at)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,now()+interval '10 minutes')`,
      [
        id,
        provider,
        input.client,
        hash(state),
        input.codeChallenge,
        verifier,
        user?.id ?? null,
        user?.authTokenVersion ?? null,
      ],
    );
    const url = new URL(
      provider === 'google'
        ? 'https://accounts.google.com/o/oauth2/v2/auth'
        : 'https://github.com/login/oauth/authorize',
    );
    const params = {
      client_id: config.clientId,
      redirect_uri: config.redirectUri,
      response_type: 'code',
      state,
      code_challenge: challenge(verifier),
      code_challenge_method: 'S256',
      scope:
        provider === 'google' ? 'openid email profile' : 'read:user user:email',
    };
    Object.entries(params).forEach(([key, value]) =>
      url.searchParams.set(key, value),
    );
    if (provider === 'google') url.searchParams.set('prompt', 'select_account');
    return {
      flowId: id,
      authorizationUrl: url.toString(),
      expiresInSeconds: 600,
    };
  }
  async callback(
    provider: string,
    input: { state?: string; code?: string; error?: string },
  ) {
    const config = this.config(provider);
    if (
      typeof input.state !== 'string' ||
      !/^[A-Za-z0-9_-]{43}$/.test(input.state)
    )
      throw new BadRequestException('Invalid or expired sign-in state.');
    const [rows] = await this.db.query<[Flow[], number]>(
      `UPDATE auth_oauth_flows SET status='processing'
      WHERE provider=$1 AND state_hash=$2 AND status='pending' AND expires_at>now() RETURNING *`,
      [provider, hash(input.state)],
    );
    const flow = rows[0];
    if (!flow)
      throw new BadRequestException('Invalid or expired sign-in state.');
    let identity: Identity | null = null,
      error: string | null = null;
    try {
      if (input.error) error = 'cancelled';
      else {
        if (
          typeof input.code !== 'string' ||
          !input.code ||
          input.code.length > 4096
        )
          throw new Error('Invalid code');
        identity = await this.providerIdentity(
          provider as OAuthProvider,
          input.code,
          flow.provider_verifier,
          config,
        );
      }
    } catch {
      error = 'provider_failed';
    }
    const completionCode = random();
    await this.db.query(
      `UPDATE auth_oauth_flows SET status='ready', provider_verifier=NULL,
      identity=$2, error_code=$3, completion_hash=$4, expires_at=LEAST(expires_at,now()+interval '2 minutes') WHERE id=$1`,
      [
        flow.id,
        identity ? JSON.stringify(identity) : null,
        error,
        hash(completionCode),
      ],
    );
    return { client: flow.client, flowId: flow.id, completionCode };
  }
  async exchange(
    input: { flowId?: string; code?: string; verifier?: string },
    bearer?: string,
  ) {
    if (
      !input ||
      typeof input.flowId !== 'string' ||
      typeof input.code !== 'string' ||
      typeof input.verifier !== 'string' ||
      !/^[A-Za-z0-9_-]{43}$/.test(input.flowId ?? '') ||
      !/^[A-Za-z0-9_-]{43}$/.test(input.code ?? '') ||
      !/^[A-Za-z0-9._~-]{43,128}$/.test(input.verifier ?? '')
    )
      throw new BadRequestException('Invalid sign-in completion.');
    const human = bearer
      ? await this.auth.authenticateHumanToken(bearer)
      : null;
    const result = await this.db.transaction(async (manager) => {
      const flows: Flow[] = await manager.query(
        `SELECT * FROM auth_oauth_flows WHERE id=$1 AND completion_hash=$2
        AND status='ready' AND expires_at>now() FOR UPDATE`,
        [input.flowId, hash(input.code!)],
      );
      const flow = flows[0];
      if (!flow || flow.client_challenge !== challenge(input.verifier!))
        throw new BadRequestException('Invalid or expired sign-in completion.');
      if (flow.link_user_id) {
        const user = human
          ? await manager.getRepository(UserEntity).findOneBy({ id: human.id })
          : null;
        if (
          !user ||
          user.id !== flow.link_user_id ||
          user.authTokenVersion !== flow.link_token_version
        )
          throw new UnauthorizedException(
            'Sign in again before linking this provider.',
          );
      }
      await manager.query(
        `UPDATE auth_oauth_flows SET status='consumed',identity=NULL,completion_hash=NULL WHERE id=$1`,
        [flow.id],
      );
      if (flow.error_code) return { error: flow.error_code };
      const resolved = await this.resolveIdentity(manager, flow);
      return 'error' in resolved
        ? resolved
        : {
            ...resolved,
            expectedTokenVersion: flow.link_token_version ?? undefined,
          };
    });
    if (!('userId' in result))
      throw new BadRequestException(this.errorMessage(result.error));
    return this.auth.createOAuthSession(
      result.userId,
      result.expectedTokenVersion,
    );
  }
  private errorMessage(code: string) {
    return (
      (
        {
          cancelled: 'Sign-in was cancelled. Please try again.',
          provider_failed:
            'Unable to verify the provider account. Check that it has a verified email and try again.',
          email_exists:
            'An account already uses this email. Sign in with your existing method, then link this provider in account settings.',
          identity_exists:
            'This provider is already linked to another account.',
          provider_exists:
            'Your account already has a different identity linked to this provider.',
        } as Record<string, string>
      )[code] ?? 'Unable to complete sign-in. Please try again.'
    );
  }
  private async resolveIdentity(
    manager: EntityManager,
    flow: Flow,
  ): Promise<{ userId: string } | { error: string }> {
    const identity = flow.identity;
    // Serialize first sign-in/linking, including two providers presenting the same email.
    await manager.query('SELECT pg_advisory_xact_lock(hashtext($1))', [
      'oauth-identity-resolution',
    ]);
    const [existing] = await manager.query<{ user_id: string }[]>(
      'SELECT user_id FROM auth_identities WHERE provider=$1 AND subject=$2',
      [flow.provider, identity.subject],
    );
    if (existing)
      return flow.link_user_id && existing.user_id !== flow.link_user_id
        ? { error: 'identity_exists' }
        : { userId: existing.user_id };
    let userId = flow.link_user_id;
    if (userId) {
      const linked = await manager.query<unknown[]>(
        'SELECT 1 FROM auth_identities WHERE user_id=$1 AND provider=$2',
        [userId, flow.provider],
      );
      if (linked.length) return { error: 'provider_exists' };
    } else {
      const repo = manager.getRepository(UserEntity);
      if (await repo.findOneBy({ email: identity.email }))
        return { error: 'email_exists' };
      const user = await repo.save(
        repo.create({
          email: identity.email,
          username: `user_${randomBytes(10).toString('hex')}`,
          displayName: identity.name,
          authProvider: flow.provider as AuthProvider,
          providerSubject: identity.subject,
          avatarUrl: identity.avatar,
          emailVerifiedAt: new Date(),
        }),
      );
      userId = user.id;
    }
    await manager.query(
      'INSERT INTO auth_identities(provider,subject,user_id) VALUES ($1,$2,$3)',
      [flow.provider, identity.subject, userId],
    );
    return { userId };
  }
  private async providerIdentity(
    provider: OAuthProvider,
    code: string,
    verifier: string,
    config: { clientId: string; clientSecret: string; redirectUri: string },
  ): Promise<Identity> {
    const token = (await this.json(
      provider === 'google'
        ? 'https://oauth2.googleapis.com/token'
        : 'https://github.com/login/oauth/access_token',
      {
        method: 'POST',
        headers: {
          'content-type': 'application/x-www-form-urlencoded',
          accept: 'application/json',
        },
        body: new URLSearchParams({
          client_id: config.clientId,
          client_secret: config.clientSecret,
          redirect_uri: config.redirectUri,
          grant_type: 'authorization_code',
          code,
          code_verifier: verifier,
        }).toString(),
      },
    )) as Record<string, unknown>;
    if (
      typeof token.access_token !== 'string' ||
      !token.access_token ||
      String(token.token_type).toLowerCase() !== 'bearer'
    )
      throw new Error('Invalid provider token');
    const headers = {
      authorization: `Bearer ${token.access_token}`,
      accept: 'application/json',
      'user-agent': 'AgentsChat',
    };
    const profile = (await this.json(
      provider === 'google'
        ? 'https://openidconnect.googleapis.com/v1/userinfo'
        : 'https://api.github.com/user',
      { headers },
    )) as Record<string, unknown>;
    let email: unknown = profile.email;
    const subject =
      provider === 'google'
        ? profile.sub
        : Number.isSafeInteger(profile.id)
          ? String(profile.id)
          : null;
    if (provider === 'google' && profile.email_verified !== true)
      throw new Error('Email not verified');
    if (provider === 'github') {
      const emails = (await this.json('https://api.github.com/user/emails', {
        headers,
      })) as { email: string; verified: boolean; primary: boolean }[];
      if (!Array.isArray(emails)) throw new Error('Missing verified email');
      email = (
        emails.find(
          (item) => item.verified === true && item.primary === true,
        ) ?? emails.find((item) => item.verified === true)
      )?.email;
    }
    if (
      typeof subject !== 'string' ||
      !subject ||
      subject.length > 255 ||
      typeof email !== 'string' ||
      email.length > 320 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
    )
      throw new Error('Invalid provider identity');
    const name = typeof profile.name === 'string' ? profile.name.trim() : '';
    const avatar = provider === 'google' ? profile.picture : profile.avatar_url;
    return {
      subject,
      email: email.trim().toLowerCase(),
      name: (name || email.split('@')[0]).slice(0, 120),
      avatar:
        typeof avatar === 'string' &&
        avatar.startsWith('https://') &&
        avatar.length <= 1024
          ? avatar
          : null,
    };
  }
  private async json(url: string, init: RequestInit): Promise<unknown> {
    const response = await fetch(url, {
      ...init,
      redirect: 'error',
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error('Provider request failed');
    return response.json();
  }
}
