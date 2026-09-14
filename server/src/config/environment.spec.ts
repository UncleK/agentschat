import { loadEnvironment } from './environment';

function productionEnvironment(): NodeJS.ProcessEnv {
  return {
    NODE_ENV: 'production',
    DATABASE_URL: 'postgres://test:test@127.0.0.1:55434/test',
    REDIS_URL: 'redis://127.0.0.1:56379',
    JWT_SECRET: 'a'.repeat(48),
    OPERATOR_TOKEN: 'b'.repeat(48),
    AGENT_CANT_SECRET: 'c'.repeat(48),
    MINIO_ENDPOINT: '127.0.0.1',
    MINIO_ACCESS_KEY: 'agentschat-test',
    MINIO_SECRET_KEY: 'd'.repeat(48),
    MAIL_DELIVERY_MODE: 'disabled',
  };
}

describe('production deployment configuration', () => {
  it('binds production to loopback by default', () => {
    expect(loadEnvironment(productionEnvironment()).host).toBe('127.0.0.1');
  });

  it.each([
    'JWT_SECRET',
    'OPERATOR_TOKEN',
    'AGENT_CANT_SECRET',
    'MINIO_SECRET_KEY',
  ])('rejects placeholder %s before serving requests', (key) => {
    expect(() =>
      loadEnvironment({ ...productionEnvironment(), [key]: 'replace-me' }),
    ).toThrow(key);
  });

  it('prevents logging real verification codes in production', () => {
    expect(() =>
      loadEnvironment({
        ...productionEnvironment(),
        MAIL_DELIVERY_MODE: 'log',
      }),
    ).toThrow('MAIL_DELIVERY_MODE=log');
  });

  it('requires the Resend key when mail delivery is enabled', () => {
    expect(() =>
      loadEnvironment({
        ...productionEnvironment(),
        MAIL_DELIVERY_MODE: 'resend',
      }),
    ).toThrow('MAIL_RESEND_API_KEY');
  });
});
