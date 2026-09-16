import request from 'supertest';
import {
  createTestApplication,
  type TestApplicationContext,
} from '../support/test-app';
describe('Authentication request limits', () => {
  let context: TestApplicationContext;
  beforeAll(async () => {
    context = await createTestApplication();
    // Own the listener for the full concurrency test. Supertest otherwise closes
    // its temporary listener after the first response while peers are in flight.
    await context.app.listen(0, '127.0.0.1');
  });
  afterAll(async () => {
    await context?.close();
  });
  it('atomically limits parallel login guesses and keeps other accounts usable', async () => {
    const replies = await Promise.all(
      Array.from({ length: 16 }, () =>
        request(context.app.getHttpServer())
          .post('/api/v1/auth/login/email')
          .send({
            email: 'limits@example.test',
            password: 'WrongPassword123!',
          }),
      ),
    );
    expect(replies.filter((r) => r.status === 401)).toHaveLength(12);
    expect(replies.filter((r) => r.status === 429)).toHaveLength(4);
    const limited = replies.find((r) => r.status === 429)!;
    expect(Number(limited.headers['retry-after'])).toBeGreaterThan(0);
    await request(context.app.getHttpServer())
      .post('/api/v1/auth/login/email')
      .send({ email: 'different@example.test', password: 'WrongPassword123!' })
      .expect(401);
    const persisted = await context.dataSource.query<Array<{ count: string }>>(
      'SELECT COUNT(*) AS count FROM auth_request_limits',
    );
    expect(Number(persisted[0].count)).toBeGreaterThan(1);
  });
  it('limits reset-code guesses even for unknown accounts and normalizes email case', async () => {
    for (let i = 0; i < 6; i++)
      await request(context.app.getHttpServer())
        .post('/api/v1/auth/password-reset/confirm')
        .send({
          email: i % 2 ? 'RESET@example.test' : 'reset@example.test',
          code: '000000',
          newPassword: 'ValidPassword123!',
        })
        .expect(400);
    await request(context.app.getHttpServer())
      .post('/api/v1/auth/password-reset/confirm')
      .set('X-Forwarded-For', '203.0.113.99')
      .send({
        email: 'reset@example.test',
        code: '000001',
        newPassword: 'ValidPassword123!',
      })
      .expect(429);
  });
});
