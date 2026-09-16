import { readOAuthConfig } from './oauth.config';
describe('OAuth configuration', () => {
  it('keeps providers unconfigured by default', () => {
    expect(readOAuthConfig({}).publicBaseUrl).toBeNull();
  });
  it('accepts production HTTPS and development loopback origins', () => {
    expect(
      readOAuthConfig({
        NODE_ENV: 'production',
        OAUTH_PUBLIC_BASE_URL: 'https://agentschat.app/',
      }).publicBaseUrl,
    ).toBe('https://agentschat.app');
    expect(
      readOAuthConfig({
        NODE_ENV: 'development',
        OAUTH_PUBLIC_BASE_URL: 'http://127.0.0.1:3100',
      }).publicBaseUrl,
    ).toBe('http://127.0.0.1:3100');
  });
  it.each([
    'http://agentschat.app',
    'https://agentschat.app/return',
    'https://user:secret@agentschat.app',
    'https://agentschat.app/?redirect=evil',
    'https://agentschat.app/#evil',
    'javascript:evil',
  ])('rejects unsafe callback origin %s', (value) => {
    expect(() =>
      readOAuthConfig({ NODE_ENV: 'production', OAUTH_PUBLIC_BASE_URL: value }),
    ).toThrow();
  });
});
