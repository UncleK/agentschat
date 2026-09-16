import { createHash, randomBytes } from 'node:crypto';
import request from 'supertest';
import {
  createTestApplication,
  TestApplicationContext,
} from '../support/test-app';
import { AuthEmailDeliveryService } from '../../src/modules/auth/auth-email-delivery.service';
import { UserEntity } from '../../src/database/entities/user.entity';

interface TestBody {
  authorizationUrl: string;
  flowId: string;
  completionCode: string;
  providers: { id: string; enabled: boolean }[];
  identities: { provider: string }[];
  accessToken: string;
  message: string;
  emailVerification: { status: string; retryAfterSeconds: number };
  user: {
    id: string;
    email: string;
    authProvider: string;
    emailVerified: boolean;
  };
}
const read = (response: { body: unknown }) => response.body as TestBody;
const nonce = () => randomBytes(32).toString('base64url');
const challenge = (value: string) =>
  createHash('sha256').update(value).digest('base64url');
describe('OAuth and registration delivery (e2e)', () => {
  let ctx: TestApplicationContext;
  let providerFetch: jest.SpyInstance;
  let sendMail: jest.SpyInstance;
  let subject = 'google-subject',
    email = 'oauth@example.test',
    verified = true;
  let verificationCode = '';
  const envKeys = [
    'OAUTH_PUBLIC_BASE_URL',
    'GOOGLE_CLIENT_ID',
    'GOOGLE_CLIENT_SECRET',
    'GITHUB_CLIENT_ID',
    'GITHUB_CLIENT_SECRET',
    'MAIL_DELIVERY_MODE',
  ] as const;
  const previous = Object.fromEntries(
    envKeys.map((key) => [key, process.env[key]]),
  );
  beforeAll(async () => {
    Object.assign(process.env, {
      OAUTH_PUBLIC_BASE_URL: 'http://127.0.0.1:3100',
      GOOGLE_CLIENT_ID: 'google-test-client',
      GOOGLE_CLIENT_SECRET: 'google-test-secret',
      GITHUB_CLIENT_ID: 'github-test-client',
      GITHUB_CLIENT_SECRET: 'github-test-secret',
      MAIL_DELIVERY_MODE: 'log',
    });
    ctx = await createTestApplication();
    sendMail = jest
      .spyOn(ctx.app.get(AuthEmailDeliveryService), 'sendEmailVerificationCode')
      .mockImplementation((input) => {
        verificationCode = input.code;
        return Promise.resolve();
      });
    providerFetch = jest
      .spyOn(globalThis, 'fetch')
      .mockImplementation((url, init) => {
        const target =
          typeof url === 'string'
            ? url
            : url instanceof URL
              ? url.href
              : url.url;
        let data: unknown;
        if (
          target === 'https://oauth2.googleapis.com/token' ||
          target === 'https://github.com/login/oauth/access_token'
        ) {
          const params = new URLSearchParams(
            typeof init?.body === 'string' ? init.body : '',
          );
          expect(params.get('code_verifier')).toMatch(/^[A-Za-z0-9_-]{43}$/);
          expect(params.get('client_secret')).toMatch(/test-secret$/);
          expect(init?.redirect).toBe('error');
          data = { access_token: 'provider-test-access', token_type: 'Bearer' };
        } else if (
          target === 'https://openidconnect.googleapis.com/v1/userinfo'
        )
          data = {
            sub: subject,
            email,
            email_verified: verified,
            name: 'OAuth Person',
          };
        else if (target === 'https://api.github.com/user')
          data = { id: 4567, name: 'GitHub Person', email: null };
        else if (target === 'https://api.github.com/user/emails')
          data = [
            {
              email: 'unverified@example.test',
              verified: false,
              primary: true,
            },
            { email, verified, primary: false },
          ];
        else throw new Error('Unexpected provider URL: ' + target);
        return Promise.resolve(
          new Response(JSON.stringify(data), {
            status: 200,
            headers: { 'content-type': 'application/json' },
          }),
        );
      });
  });
  afterAll(async () => {
    jest.restoreAllMocks();
    await ctx?.close();
    for (const key of envKeys) {
      if (previous[key] === undefined) delete process.env[key];
      else process.env[key] = previous[key];
    }
  });
  const http = () => request(ctx.app.getHttpServer());
  async function start(provider = 'google', client = 'web', token?: string) {
    const verifier = nonce();
    const req = http()
      .post(`/api/v1/auth/oauth/${provider}/${token ? 'link' : 'start'}`)
      .send({ client, codeChallenge: challenge(verifier) });
    if (token) req.set('Authorization', 'Bearer ' + token);
    const response = await req.expect(200);
    const body = read(response);
    const url = new URL(body.authorizationUrl);
    expect(url.searchParams.get('code_challenge_method')).toBe('S256');
    expect(url.searchParams.get('redirect_uri')).toBe(
      `http://127.0.0.1:3100/api/oauth/callback/${provider}`,
    );
    expect(body).not.toHaveProperty('clientSecret');
    return {
      flowId: body.flowId,
      verifier,
      state: url.searchParams.get('state')!,
      provider,
    };
  }
  async function callback(
    flow: Awaited<ReturnType<typeof start>>,
    error?: string,
  ) {
    const response = await http()
      .get(`/api/v1/auth/oauth/${flow.provider}/callback`)
      .query({
        state: flow.state,
        ...(error ? { error } : { code: 'verified-provider-code' }),
      })
      .expect(200);
    const body = read(response);
    expect(body).not.toHaveProperty('accessToken');
    return {
      flowId: flow.flowId,
      verifier: flow.verifier,
      code: body.completionCode,
    };
  }
  it('advertises configured providers without credentials', async () => {
    const response = await http()
      .get('/api/v1/auth/oauth/providers')
      .expect(200);
    const body = read(response);
    expect(body.providers).toEqual([
      { id: 'google', enabled: true },
      { id: 'github', enabled: true },
    ]);
    await http().post('/api/v1/auth/oauth/google/link').send({}).expect(401);
    await http().post('/api/v1/auth/oauth/unknown/start').send({}).expect(400);
  });
  it('validates state and PKCE and consumes the callback and completion exactly once', async () => {
    const flow = await start();
    const proof = await callback(flow);
    await http()
      .get('/api/v1/auth/oauth/google/callback')
      .query({ state: flow.state, code: 'replay' })
      .expect(400);
    await http()
      .post('/api/v1/auth/oauth/exchange')
      .send({ ...proof, verifier: nonce() })
      .expect(400);
    const response = await http()
      .post('/api/v1/auth/oauth/exchange')
      .send(proof)
      .expect(200);
    const body = read(response);
    expect(body.user).toMatchObject({
      email,
      authProvider: 'google',
      emailVerified: true,
    });
    await http()
      .get('/api/v1/auth/me')
      .set('Authorization', 'Bearer ' + body.accessToken)
      .expect(200);
    await http().post('/api/v1/auth/oauth/exchange').send(proof).expect(400);
  });
  it('returns the same account on mobile even when the provider email changes', async () => {
    const original = await ctx.dataSource
      .getRepository(UserEntity)
      .findOneByOrFail({ email });
    email = 'new-provider-email@example.test';
    const proof = await callback(await start('google', 'mobile'));
    const response = await http()
      .post('/api/v1/auth/oauth/exchange')
      .send(proof)
      .expect(200);
    const body = read(response);
    expect(body.user.id).toBe(original.id);
    expect(body.user.email).toBe(original.email);
  });
  it('sends the verification code during registration, then verifies without requesting again', async () => {
    sendMail.mockClear();
    const response = await http()
      .post('/api/v1/auth/register/email')
      .send({
        email: 'registered@example.test',
        username: 'registered_oauth',
        displayName: 'Email Owner',
        password: 'TestPassword2026!',
      })
      .expect(201);
    const body = read(response);
    expect(sendMail).toHaveBeenCalledTimes(1);
    expect(body.emailVerification).toMatchObject({ status: 'sent' });
    expect(body).not.toHaveProperty('code');
    await http()
      .post('/api/v1/auth/email-verification/confirm')
      .set('Authorization', 'Bearer ' + body.accessToken)
      .send({ code: verificationCode === '000000' ? '000001' : '000000' })
      .expect(400);
    const [stored] = await ctx.dataSource.query<
      { user_id: string; attempt_count: number }[]
    >(
      'SELECT user_id,attempt_count FROM auth_email_codes WHERE email=$1 ORDER BY created_at DESC LIMIT 1',
      ['registered@example.test'],
    );
    expect(stored.user_id).toBe(body.user.id);
    expect(stored.attempt_count).toBe(1);
    await http()
      .post('/api/v1/auth/email-verification/request')
      .set('Authorization', 'Bearer ' + body.accessToken)
      .expect(400);
    await http()
      .post('/api/v1/auth/email-verification/confirm')
      .set('Authorization', 'Bearer ' + body.accessToken)
      .send({ code: verificationCode })
      .expect(200);
    const me = await http()
      .get('/api/v1/auth/me')
      .set('Authorization', 'Bearer ' + body.accessToken)
      .expect(200);
    expect(read(me).user.emailVerified).toBe(true);
  });
  it('requires explicit authenticated linking for an existing email and does not link at callback time', async () => {
    subject = 'linked-subject';
    email = 'registered@example.test';
    let proof = await callback(await start());
    const collision = await http()
      .post('/api/v1/auth/oauth/exchange')
      .send(proof)
      .expect(400);
    expect(read(collision).message).toContain(
      'Sign in with your existing method',
    );
    const login = await http()
      .post('/api/v1/auth/login/email')
      .send({ email, password: 'TestPassword2026!' })
      .expect(200);
    const token = read(login).accessToken;
    proof = await callback(await start('google', 'web', token));
    expect(
      read(
        await http()
          .get('/api/v1/auth/oauth/identities')
          .set('Authorization', 'Bearer ' + token),
      ).identities,
    ).toEqual([]);
    await http().post('/api/v1/auth/oauth/exchange').send(proof).expect(401);
    const linked = await http()
      .post('/api/v1/auth/oauth/exchange')
      .set('Authorization', 'Bearer ' + token)
      .send(proof)
      .expect(200);
    expect(read(linked).user.id).toBe(read(login).user.id);
    expect(read(linked).user.authProvider).toBe('email');
    proof = await callback(await start('google', 'mobile'));
    const later = await http()
      .post('/api/v1/auth/oauth/exchange')
      .send(proof)
      .expect(200);
    expect(read(later).user.id).toBe(read(login).user.id);
  });
  it('uses a verified private GitHub email and rejects unverified identities', async () => {
    email = 'github-private@example.test';
    let proof = await callback(await start('github', 'mobile'));
    const response = await http()
      .post('/api/v1/auth/oauth/exchange')
      .send(proof)
      .expect(200);
    const body = read(response);
    expect(body.user).toMatchObject({
      email,
      authProvider: 'github',
      emailVerified: true,
    });
    verified = false;
    subject = 'unverified-subject';
    proof = await callback(await start());
    await http().post('/api/v1/auth/oauth/exchange').send(proof).expect(400);
    verified = true;
  });
  it('does not complete a pending link after the owner session is revoked', async () => {
    const owner = await http()
      .post('/api/v1/auth/register/email')
      .send({
        email: 'revoked-owner@example.test',
        username: 'revoked_oauth',
        displayName: 'Revoked Owner',
        password: 'TestPassword2026!',
      })
      .expect(201);
    const token = read(owner).accessToken;
    const proof = await callback(await start('google', 'mobile', token));
    await ctx.dataSource.query(
      'UPDATE users SET auth_token_version=auth_token_version+1 WHERE id=$1',
      [read(owner).user.id],
    );
    await http()
      .post('/api/v1/auth/oauth/exchange')
      .set('Authorization', 'Bearer ' + token)
      .send(proof)
      .expect(401);
    const identities = await ctx.dataSource.query<unknown[]>(
      'SELECT * FROM auth_identities WHERE user_id=$1',
      [read(owner).user.id],
    );
    expect(identities).toHaveLength(0);
  });
  it('handles cancellation, expiry and wrong-provider state without authenticating anyone', async () => {
    const flow = await start();
    await http()
      .get('/api/v1/auth/oauth/github/callback')
      .query({ state: flow.state, code: 'wrong-provider' })
      .expect(400);
    providerFetch.mockClear();
    const proof = await callback(flow, 'access_denied');
    expect(providerFetch).not.toHaveBeenCalled();
    const result = await http()
      .post('/api/v1/auth/oauth/exchange')
      .send(proof)
      .expect(400);
    expect(read(result).message).toContain('cancelled');
    const expired = await start();
    await ctx.dataSource.query(
      "UPDATE auth_oauth_flows SET expires_at=now()-interval '1 second' WHERE id=$1",
      [expired.flowId],
    );
    await http()
      .get('/api/v1/auth/oauth/google/callback')
      .query({ state: expired.state, code: 'expired' })
      .expect(400);
  });
  it('serializes simultaneous first logins to one persistent account', async () => {
    subject = 'concurrent-subject';
    email = 'concurrent@example.test';
    const a = await callback(await start());
    const b = await callback(await start('google', 'mobile'));
    const [one, two] = await Promise.all([
      http().post('/api/v1/auth/oauth/exchange').send(a),
      http().post('/api/v1/auth/oauth/exchange').send(b),
    ]);
    expect(one.status).toBe(200);
    expect(two.status).toBe(200);
    expect(read(one).user.id).toBe(read(two).user.id);
    expect(
      await ctx.dataSource.getRepository(UserEntity).countBy({ email }),
    ).toBe(1);
  });
  it('preserves registration and allows retry after mail delivery fails', async () => {
    sendMail.mockRejectedValueOnce(new Error('Mail temporarily unavailable'));
    const response = await http()
      .post('/api/v1/auth/register/email')
      .send({
        email: 'mail-outage@example.test',
        username: 'mail_outage',
        displayName: 'Mail Outage',
        password: 'TestPassword2026!',
      })
      .expect(201);
    const body = read(response);
    expect(body.emailVerification).toEqual({
      status: 'failed',
      retryAfterSeconds: 0,
    });
    await http()
      .get('/api/v1/auth/me')
      .set('Authorization', 'Bearer ' + body.accessToken)
      .expect(200);
    await http()
      .post('/api/v1/auth/email-verification/request')
      .set('Authorization', 'Bearer ' + body.accessToken)
      .expect(200);
    await http()
      .post('/api/v1/auth/email-verification/confirm')
      .set('Authorization', 'Bearer ' + body.accessToken)
      .send({ code: verificationCode })
      .expect(200);
  });
  it('keeps password-reset codes usable after a mistyped code and revokes the old session', async () => {
    let resetCode = '';
    jest
      .spyOn(ctx.app.get(AuthEmailDeliveryService), 'sendPasswordResetCode')
      .mockImplementation((input) => {
        resetCode = input.code;
        return Promise.resolve();
      });
    const owner = await http()
      .post('/api/v1/auth/login/email')
      .send({
        email: 'mail-outage@example.test',
        password: 'TestPassword2026!',
      })
      .expect(200);
    await http()
      .post('/api/v1/auth/password-reset/request')
      .send({ email: 'mail-outage@example.test' })
      .expect(200);
    await http()
      .post('/api/v1/auth/password-reset/confirm')
      .send({
        email: 'mail-outage@example.test',
        code: resetCode === '000000' ? '000001' : '000000',
        newPassword: 'ChangedPassword2026!',
      })
      .expect(400);
    await http()
      .post('/api/v1/auth/password-reset/confirm')
      .send({
        email: 'mail-outage@example.test',
        code: resetCode,
        newPassword: 'ChangedPassword2026!',
      })
      .expect(200);
    await http()
      .get('/api/v1/auth/me')
      .set('Authorization', 'Bearer ' + read(owner).accessToken)
      .expect(401);
    const after = await http()
      .post('/api/v1/auth/login/email')
      .send({
        email: 'mail-outage@example.test',
        password: 'ChangedPassword2026!',
      })
      .expect(200);
    expect(read(after).user.id).toBe(read(owner).user.id);
  });
});
