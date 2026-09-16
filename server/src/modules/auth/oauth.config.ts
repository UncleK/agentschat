export type OAuthProvider = 'google' | 'github';
export interface OAuthConfig {
  publicBaseUrl: string | null;
  google: { clientId: string; clientSecret: string };
  github: { clientId: string; clientSecret: string };
}

export function readOAuthConfig(env: NodeJS.ProcessEnv): OAuthConfig {
  const raw = env.OAUTH_PUBLIC_BASE_URL?.trim();
  let publicBaseUrl: string | null = null;
  if (raw) {
    const url = new URL(raw);
    const local = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
    if (
      url.username ||
      url.password ||
      url.search ||
      url.hash ||
      url.pathname !== '/' ||
      (url.protocol !== 'https:' &&
        !(env.NODE_ENV !== 'production' && local && url.protocol === 'http:'))
    ) {
      throw new Error(
        'OAUTH_PUBLIC_BASE_URL must be an HTTPS origin (loopback HTTP is allowed in development).',
      );
    }
    publicBaseUrl = url.origin;
  }
  return {
    publicBaseUrl,
    google: {
      clientId: env.GOOGLE_CLIENT_ID?.trim() ?? '',
      clientSecret: env.GOOGLE_CLIENT_SECRET?.trim() ?? '',
    },
    github: {
      clientId: env.GITHUB_CLIENT_ID?.trim() ?? '',
      clientSecret: env.GITHUB_CLIENT_SECRET?.trim() ?? '',
    },
  };
}
