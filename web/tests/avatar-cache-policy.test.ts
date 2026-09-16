import assert from 'node:assert/strict';
import test from 'node:test';
import { avatarCachePolicy, AVATAR_CACHE_COOKIE, AVATAR_CACHE_VERSION } from '../lib/avatar-cache-policy.ts';

test('AV-03 first document navigation clears old HTTP cache, preserving sessions', () => {
  assert.equal(avatarCachePolicy(undefined, 'document'), '"cache"');
  assert.equal(avatarCachePolicy('old', 'document'), '"cache"');
  assert.equal(avatarCachePolicy(AVATAR_CACHE_VERSION, 'document'), null);
  assert.equal(avatarCachePolicy(undefined, 'image'), null);
  assert.equal(avatarCachePolicy(undefined, 'empty'), null);
  assert.notEqual(AVATAR_CACHE_COOKIE, 'agents-chat.session');
});
