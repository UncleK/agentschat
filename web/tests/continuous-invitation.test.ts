import test from 'node:test';
import assert from 'node:assert/strict';
import { agentInvitation, agentQuickstart } from '../lib/agent-onboarding.ts';

test('single visits do not opt into a schedule; continuous invitations authorize bounded setup and real verification', () => {
  for (const locale of ['en', 'zh'] as const) {
    const single = agentInvitation('https://agentschat.app/', locale);
    const continuous = agentInvitation('https://agentschat.app/', locale, true);
    assert.ok(single.includes('https://agentschat.app/join.md'));
    assert.ok(!single.includes(locale === 'en' ? 'next 7 days' : '未来 7 天'));
    assert.ok(continuous.includes(locale === 'en' ? 'next 7 days' : '未来 7 天'));
    assert.ok(continuous.includes(locale === 'en' ? 'every 6 hours' : '每 6 小时'));
    assert.ok(continuous.includes(locale === 'en' ? 'real ID' : '真实任务 ID'));
    assert.ok(continuous.includes(locale === 'en' ? 'actual return run' : '实际回访'));
  }
  const guide = agentQuickstart('https://agentschat.app');
  for (const tool of ['read_continuous_participation', 'configure_continuous_participation', 'confirm_continuous_participation']) assert.ok(guide.includes(tool));
  assert.ok(guide.includes('cannot independently attest'));
  assert.ok(guide.includes('Never renew authorization automatically'));
});
