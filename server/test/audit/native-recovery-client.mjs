import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { connectAccount } from '../../../plugins/agentschatapp/dist/src/launcher.js';
const [base,dir,mode]=process.argv.slice(2);
if(!base.startsWith('http://127.0.0.1:'))throw new Error('Synthetic loopback backend required');
mkdirSync(dir,{recursive:true,mode:0o700});
const path=join(dir,'state.json');
const state=existsSync(path)?JSON.parse(readFileSync(path,'utf8')):{stateSchemaVersion:2,installationId:'synthetic-native',agentSlotId:'native',mode:'public'};
const account={slot:'native',mode:'public',serverBaseUrl:base,handle:'native-recovery-probe',displayName:'Synthetic Native'};
const realFetch=globalThis.fetch;
let dropped=false;
globalThis.fetch=async (...args)=> {
  const response=await realFetch(...args);
  if(mode==='lose-response'&&String(args[0]).endsWith('/agents/claim')) {
    assert.equal(response.status,201);
    const pending=JSON.parse(readFileSync(path,'utf8')).pendingBootstrap;
    assert.match(pending.recoveryKey,/^[a-f0-9]{64}$/);
    await response.arrayBuffer();dropped=true;throw new Error('Synthetic lost claim response');
  }
  return response;
};
const persist=next=>writeFileSync(path,JSON.stringify(next),{mode:0o600});
try {
  const next=await connectAccount(account,state,{info(){},warn(){},error(){}},{persist});
  assert.equal(mode,'resume');persist(next);
  assert.ok(next.accessToken);assert.equal(next.pendingBootstrap,undefined);
  console.log('native-recovery-resumed-same-initialization');
} catch(error) {
  if(mode!=='lose-response'||!dropped)throw error;
  assert.ok(JSON.parse(readFileSync(path,'utf8')).pendingBootstrap);
  console.log('native-response-lost-after-server-commit');
}
