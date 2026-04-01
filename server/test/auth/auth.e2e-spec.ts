import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { AuthProvider } from '../../src/database/domain.enums';
import {
  TestApplicationContext,
  createTestApplication,
} from '../support/test-app';

describe('Human auth (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
  });

  afterAll(async () => {
    await context?.close();
  });

  it('registers and logs in with email/password, then uses the human token on a protected route', async () => {
    const registerResponse = await request(app.getHttpServer())
      .post('/api/v1/auth/register/email')
      .send({
        email: 'owner@example.com',
        displayName: 'Owner Human',
        password: 'password123',
      })
      .expect(201);

    expect(registerResponse.body.user.email).toBe('owner@example.com');
    expect(registerResponse.body.user.authProvider).toBe(AuthProvider.Email);
    expect(registerResponse.body.accessToken).toEqual(expect.any(String));

    const loginResponse = await request(app.getHttpServer())
      .post('/api/v1/auth/login/email')
      .send({
        email: 'owner@example.com',
        password: 'password123',
      })
      .expect(200);

    expect(loginResponse.body.user.id).toBe(registerResponse.body.user.id);
    expect(loginResponse.body.accessToken).toEqual(expect.any(String));

    const importedAgentResponse = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${loginResponse.body.accessToken}`)
      .send({
        handle: 'owner-agent',
        displayName: 'Owner Agent',
      })
      .expect(201);

    expect(importedAgentResponse.body.ownerType).toBe('human');
    expect(importedAgentResponse.body.ownerUserId).toBe(registerResponse.body.user.id);
  });

  it('represents Google and GitHub auth flows at the API layer', async () => {
    const googleResponse = await request(app.getHttpServer())
      .post('/api/v1/auth/login/google')
      .send({
        email: 'google-user@example.com',
        displayName: 'Google User',
        providerSubject: 'google-subject-1',
      })
      .expect(200);

    expect(googleResponse.body.user.authProvider).toBe(AuthProvider.Google);
    expect(googleResponse.body.accessToken).toEqual(expect.any(String));

    const repeatedGoogleResponse = await request(app.getHttpServer())
      .post('/api/v1/auth/login/google')
      .send({
        email: 'google-user@example.com',
        displayName: 'Google User Updated',
        providerSubject: 'google-subject-1',
      })
      .expect(200);

    expect(repeatedGoogleResponse.body.user.id).toBe(googleResponse.body.user.id);
    expect(repeatedGoogleResponse.body.user.displayName).toBe('Google User Updated');

    const githubResponse = await request(app.getHttpServer())
      .post('/api/v1/auth/login/github')
      .send({
        email: 'github-user@example.com',
        displayName: 'GitHub User',
        providerSubject: 'github-subject-1',
      })
      .expect(200);

    expect(githubResponse.body.user.authProvider).toBe(AuthProvider.GitHub);
    expect(githubResponse.body.accessToken).toEqual(expect.any(String));
  });
});
