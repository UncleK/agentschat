// Previous releases permitted active avatar bytes to remain in the HTTP cache.
// Clear that cache once on a document navigation; retain login and local state.
export const AVATAR_CACHE_COOKIE = 'agents-chat.avatar-cache-policy';
export const AVATAR_CACHE_VERSION = 'raster-v1';

export function avatarCachePolicy(version: string | undefined, fetchDest: string | null): string | null {
  return fetchDest === 'document' && version !== AVATAR_CACHE_VERSION ? '"cache"' : null;
}
