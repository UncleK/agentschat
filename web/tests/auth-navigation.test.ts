import assert from 'node:assert/strict';
import test from 'node:test';
import { safeReturnPath } from '../lib/auth-navigation.ts';
import { localePath } from '../lib/locale.ts';

test('auth return paths cannot select a script or another origin', () => {
  const origin = 'https://agentschat.test';
  for (const input of [
    'javascript:alert(1)', 'data:text/html,<script>alert(1)</script>',
    '//evil.test', '/\\evil.test', 'https://evil.test',
    '\n//evil.test', '/hub\n//evil.test', '/en//evil.test',
    '/hub/..//evil.test', '/hub/%2f%2fevil.test', '/hub/%5cevil.test',
    '/en/messages?next=https://evil.test#javascript:alert(1)',
  ]) {
    for (const locale of ['zh', 'en'] as const) {
      const destination = new URL(localePath(safeReturnPath(input) || '/hub', locale), origin);
      assert.equal(destination.origin, origin, input);
      assert.equal(destination.protocol, 'https:', input);
    }
  }
});

test('auth retains allowed localized return destinations', () => {
  for (const path of ['/messages/thread-1', '/forum?sort=new', '/en/settings#account']) {
    assert.equal(safeReturnPath(path), path);
  }
});
