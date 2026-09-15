import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync, fork } from 'node:child_process';
import { createAgentsChatStateStore, loadSlotState, saveSlotState, resolveSlotStateFilePath } from '../dist/src/state.js';

test('ST-03 stale worker cannot overwrite a rotated credential or change identity', () => {
  const root = mkdtempSync(join(tmpdir(), 'agentschat-state-audit-'));
  try {
    const store = createAgentsChatStateStore(root);
    const initial = {stateSchemaVersion:1, installationId:'synthetic-install', agentSlotId:'fixture', mode:'public'};
    initial.agentId = 'synthetic-agent'; initial.accessToken = 'synthetic-original';
    saveSlotState('fixture', initial, store);
    const stale = loadSlotState('fixture', store);
    const current = loadSlotState('fixture', store);
    current.accessToken = 'synthetic-rotated'; saveSlotState('fixture', current, store);
    assert.throws(() => saveSlotState('fixture', stale, store), /stale state/);
    assert.equal(loadSlotState('fixture', store).accessToken, 'synthetic-rotated');
    assert.equal(loadSlotState('fixture', store).agentId, initial.agentId);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('ST-02 credential file grants access only to its OS owner', () => {
  const root = mkdtempSync(join(tmpdir(), 'agentschat-acl-audit-'));
  try {
    const store = createAgentsChatStateStore(root);
    const state = {stateSchemaVersion:1, installationId:'synthetic-install', agentSlotId:'fixture', mode:'public'};
    state.accessToken = 'synthetic-only'; saveSlotState('fixture', state, store);
    const path = resolveSlotStateFilePath('fixture', store);
    if (process.platform === 'win32') {
      const script = '$ErrorActionPreference="Stop"; $ProgressPreference="SilentlyContinue"; $a=[System.IO.File]::GetAccessControl($env:AGENTSCHAT_ACL_TEST_PATH); [pscustomobject]@{protected=$a.AreAccessRulesProtected; identities=@($a.Access | ForEach-Object {$_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value}); user=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value} | ConvertTo-Json -Compress';
      const acl = JSON.parse(execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(script, 'utf16le').toString('base64')], { encoding: 'utf8', windowsHide: true, env: { ...process.env, AGENTSCHAT_ACL_TEST_PATH: path } }));
      assert.equal(acl.protected, true);
      assert.deepEqual(acl.identities, [acl.user]);
    } else assert.equal(statSync(path).mode & 0o777, 0o600);
    assert.equal(JSON.parse(readFileSync(path, 'utf8')).accessToken, 'synthetic-only');
  } finally { rmSync(root, { recursive: true, force: true }); }
});


test('ST-03 killed writer leaves a complete old JSON before atomic rename', async () => {
  const root = mkdtempSync(join(tmpdir(), 'agentschat-kill-audit-'));
  let child;
  try {
    const store = createAgentsChatStateStore(root);
    const state = {stateSchemaVersion:1, installationId:'synthetic-install', agentSlotId:'fixture', mode:'public'};
    state.agentId = 'original-synthetic'; state.accessToken = 'original-synthetic-token';
    saveSlotState('fixture', state, store);
    const path = resolveSlotStateFilePath('fixture', store);
    child = fork(new URL('./state-writer.fixture.mjs', import.meta.url), [], { env: { ...process.env, AUDIT_STATE_KILL_PATH: path }, stdio: ['ignore','ignore','pipe','ipc'] });
    await new Promise((resolve, reject) => { const timer = setTimeout(() => reject(new Error('writer did not reach rename')),10000); child.once('message', () => { clearTimeout(timer); resolve(); }); child.once('error', reject); });
    await new Promise(resolve => { child.once('exit', resolve); child.kill('SIGKILL'); });
    assert.equal(loadSlotState('fixture', store).agentId, 'original-synthetic');
    assert.equal(loadSlotState('fixture', store).accessToken, 'original-synthetic-token');
  } finally { child?.kill(); rmSync(root, { recursive: true, force: true }); }
});


test('ST-03 two processes with the same revision cannot mix or overwrite credential generations', async () => {
  const root = mkdtempSync(join(tmpdir(),'agentschat-concurrent-audit-'));
  const children=[];
  try {
    const store=createAgentsChatStateStore(root);
    const initial={stateRevision:0,stateSchemaVersion:1,installationId:'synthetic-install',agentSlotId:'fixture',mode:'public',agentId:'synthetic-existing',accessToken:'original'};
    saveSlotState('fixture',initial,store);
    const ready=[]; const outcomes=[];
    for(const token of ['candidate-a','candidate-b']) {
      const child=fork(new URL('./state-writer.fixture.mjs',import.meta.url),[],{env:{...process.env,AUDIT_STATE_CONCURRENT_ROOT:store.pluginStateRoot,AUDIT_STATE_CANDIDATE:JSON.stringify({...initial,accessToken:token})},stdio:['ignore','ignore','pipe','ipc']});
      children.push(child);
      ready.push(new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('writer not ready')),10000);child.once('message',()=>{clearTimeout(timer);resolve();});}));
      outcomes.push(new Promise(resolve=>child.on('message',m=>{if(m.status!=='ready')resolve({...m,token});})));
    }
    await Promise.all(ready); children.forEach(child=>child.send('write'));
    const results=await Promise.all(outcomes);
    const winner=results.find(r=>r.status==='saved');
    assert.equal(results.filter(r=>r.status==='saved').length,1);
    assert.match(results.find(r=>r.status==='rejected').message,/stale state/);
    const saved=loadSlotState('fixture',store);
    assert.equal(saved.accessToken,winner.token);assert.equal(saved.agentId,initial.agentId);
    assert.equal(saved.stateRevision,initial.stateRevision+1);
    await Promise.all(children.map(child=>child.exitCode!==null?Promise.resolve():new Promise(resolve=>child.once('exit',resolve))));
  } finally {children.forEach(child=>child.kill());rmSync(root,{recursive:true,force:true});}
});
