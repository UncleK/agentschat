import assert from 'node:assert/strict';
import { test } from 'node:test';
import { confirmClaimLauncher, connectAccount } from '../dist/src/launcher.js';
import { DEFAULT_RUNTIME_NAME, DEFAULT_VENDOR_NAME } from '../dist/src/constants.js';

const state = { mode: 'public', agentId: 'synthetic-agent', accessToken: 'synthetic-agent-token', serverBaseUrl: 'https://fixture.invalid', agentSlotId: 'one', installationId: 'synthetic-install' };
const launcher = 'agents-chat://launch?mode=claim&claimRequestId=synthetic-request&challengeToken=synthetic-challenge';
test('AI-02 no human approval means no request; social or old launcher cannot silently confirm', async () => {
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url) => { calls.push(url); return Response.json({ purpose: 'bind_account', agentId: state.agentId, accountId: 'synthetic-human' }); };
  try {
    await assert.rejects(confirmClaimLauncher(state, launcher), /authenticated human/);
    assert.equal(calls.length, 0);
    await assert.rejects(confirmClaimLauncher(state, launcher, { humanAccessToken: 'synthetic-human-token', approve: async () => false }), /not approved/);
    assert.equal(calls.length, 1);
    assert.match(calls[0], /control-preview$/);
  } finally { globalThis.fetch = original; }
});
test('AI-02 deterministic approval binds exactly the previewed account with both credentials', async () => {
  const original = globalThis.fetch; const calls = [];
  globalThis.fetch = async (url, options) => { calls.push({url,options}); return Response.json({ purpose: 'bind_account', agentId: state.agentId, accountId: 'synthetic-human' }); };
  try {
    await confirmClaimLauncher(state, launcher, { humanAccessToken: 'synthetic-human-token', approve: async p => p.accountId === 'synthetic-human' });
    assert.equal(calls.length,2);
    const sent = JSON.parse(calls[1].options.body);
    assert.deepEqual(sent.authorization, { purpose:'bind_account', accountId:'synthetic-human', agentId:state.agentId, approved:true });
    assert.equal(new Headers(calls[1].options.headers).get('authorization'), 'Bearer synthetic-human-token');
    assert.equal(new Headers(calls[1].options.headers).get('x-agent-control-token'), state.accessToken);
    assert.equal(calls[1].options.redirect,'error');
  } finally { globalThis.fetch=original; }
});
test('ON-03 public restart preserves existing identity and refuses revoked-token rebootstrap', async () => {
  const original = globalThis.fetch; const calls = [];
  const account = {mode:'public',slot:'one',openclawAgent:'fixture',serverBaseUrl:state.serverBaseUrl};
  const persisted = {...state,runtimeName:DEFAULT_RUNTIME_NAME,vendorName:DEFAULT_VENDOR_NAME,lastProfileSyncFingerprint:JSON.stringify({handle:null,displayName:null,bio:null,profileTags:[],avatarEmoji:null,avatarFilePath:null,avatarFileFingerprint:null,runtimeName:DEFAULT_RUNTIME_NAME,vendorName:DEFAULT_VENDOR_NAME})};
  let revoked = false;
  globalThis.fetch=async url => {calls.push(url); return Response.json(revoked ? {code:'invalid_agent_token'} : {}, {status:revoked ? 401:200});};
  try {
    const resumed = await connectAccount(account, JSON.parse(JSON.stringify(persisted)), {warn:()=>{}});
    assert.equal(resumed.agentId,state.agentId); assert.equal(resumed.accessToken,state.accessToken);
    revoked=true;
    await assert.rejects(connectAccount(account,persisted,{warn:()=>{}}), /no longer resume/);
    assert.ok(calls.every(url=>!url.includes('/bootstrap')&&!url.endsWith('/claim')));
  } finally {globalThis.fetch=original;}
});
