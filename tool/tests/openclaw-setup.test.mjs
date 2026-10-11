import {test} from 'node:test';
import assert from 'node:assert/strict';
import {resolve} from 'node:path';
import {prepare, confirm, parseInvite, operatorCommand} from '../../web/public/downloads/openclaw-setup.mjs';
const requestId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const agentId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const accountId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const deviceId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const challengeToken = 'claimreq.v1.' + 'a'.repeat(48);
const origin = 'https://agentschat.app';
const credentialPath = resolve('output/test-private/slots/example/state.json');
const expiresAt = () => new Date(Date.now()+600000).toISOString();
function link() {return origin+'/openclaw#invite='+Buffer.from(JSON.stringify({v:1,requestId,challengeToken,expiresAt:expiresAt()})).toString('base64url');}
function fixture(version='0.2.0') {
  const cli = [], calls = [], files = new Map([[credentialPath, {agentId, accessToken:'PRIVATE_AGENT_BEARER',serverBaseUrl:origin}]]);
  let installed = version;
  const deps = {
    run: async args => {
      cli.push(args);
      if (args[0]==='plugins' && args[1]==='list') return JSON.stringify({plugins: installed ? [{id:'agentschatapp',version:installed}] : []});
      if (args[0]==='plugins') {installed='0.2.0';return '';}
      if (args[1]==='connect') return JSON.stringify({status:'connected',slot:'example',agentId,serverBaseUrl:origin});
      return JSON.stringify({accounts:[{slot:'example',config:{openclawAgent:'local'},persistedState:{path:credentialPath,agentId,serverBaseUrl:origin}}]});
    },
    read: path => files.get(path), exists: path => files.has(path), write:(path,data)=>files.set(path,data),
    http:async (base,path,token,body) => {
      calls.push({base,path,token,body});
      if(path.endsWith('/preview')) return {status:'ready',requestId,agentId,accountId,accountName:'Owner',handle:'example'};
      if(path==='/binding-devices') return {id:deviceId,deviceSecret:'e'.repeat(64),verificationPath:'/binding/authorize?code='+'f'.repeat(24),expiresAt:expiresAt()};
      if(path.endsWith('/poll')) return {status:'approved',purpose:'bind_account',requestId,agentId,accountId,accountName:'Owner'};
      return {agent:{id:agentId,handle:'example',ownerUserId:accountId}};
    },
  };
  return {deps,cli,calls,files};
}
test('private fragment is required, expiry and another origin fail before installation', async()=> {
  assert.equal(parseInvite(link()).requestId,requestId);
  assert.throws(()=>parseInvite(origin+'/openclaw'),/fragment/);
  assert.throws(()=>parseInvite(link().replace(origin,'https://other.example')),/official/);
  const expired=origin+'/openclaw#invite='+Buffer.from(JSON.stringify({v:1,requestId,challengeToken,expiresAt:'2000-01-01'})).toString('base64url');
  assert.throws(()=>parseInvite(expired),/expired/);
});
test('missing plugin installs pinned version; existing and newer versions are reused', async()=> {
  for(const version of [null,'0.2.0','0.3.0']) {
    const f=fixture(version); const result=await prepare(link(),{},f.deps);
    assert.equal(result.pluginAction,version?'reused':'installed');
    assert.equal(f.cli.filter(args=>args[1]==='install').length,version?0:1);
    assert.equal(result.status,'awaiting_owner_confirmation');assert.equal(result.verified,false);
    assert.equal(f.calls.some(call=>call.path.endsWith('/confirm')),false);
    assert.ok(f.cli.find(args=>args[1]==='connect').includes('false'));
    const output=JSON.stringify(result);
    for(const secret of ['PRIVATE_AGENT_BEARER',challengeToken,'e'.repeat(64)]) assert.equal(output.includes(secret),false);
  }
});
test('old plugin updates, host installation refusal stops without joining', async()=> {
  const f=fixture('0.1.15');await prepare(link(),{},f.deps);
  assert.deepEqual(f.cli.find(args=>args[1]==='update'),['plugins','update','agentschatapp@0.2.0']);
  const blocked=fixture(null); const original=blocked.deps.run;
  blocked.deps.run=args=>args[1]==='install'?Promise.reject(new Error('owner approval required')):original(args);
  await assert.rejects(prepare(link(),{},blocked.deps),/approval/);assert.equal(blocked.calls.length,0);
});
test('same invitation reuses one device and one native identity', async()=> {
  const f=fixture();const url=link();await prepare(url,{},f.deps);await prepare(url,{},f.deps);
  assert.equal(f.calls.filter(call=>call.path==='/binding-devices').length,1);
  assert.ok(f.calls.some(call=>call.path.endsWith('/poll')));
  const other=fixture();other.deps.run=async args=>args[1]==='list'?JSON.stringify({plugins:[{id:'agentschatapp',version:'0.2.0'}]}):JSON.stringify({accounts:[{persistedState:{agentId,serverBaseUrl:'https://other.example'}}]});
  await assert.rejects(prepare(link(),{},other.deps),/different server/);
});
test('an expired browser device renews under the still-valid invitation without replacing identity', async()=> {
  const f=fixture();const url=link();await prepare(url,{},f.deps);
  const path=[...f.files.keys()].find(path=>path.includes('.agentschat-binding-'));
  f.files.get(path).expiresAt='2000-01-01';
  const result=await prepare(url,{}, {...f.deps,remove:path=>f.files.delete(path)});
  assert.equal(result.status,'awaiting_owner_confirmation');assert.equal(result.agentId,agentId);
  assert.equal(f.calls.filter(call=>call.path==='/binding-devices').length,2);
  assert.equal(f.files.get(credentialPath).agentId,agentId);
});
test('already bound is verified without issuing another device', async()=> {
  const f=fixture();const original=f.deps.http;f.deps.http=(...args)=>args[1].endsWith('/preview')?{status:'bound',requestId,agentId,handle:'example'}:original(...args);
  const result=await prepare(link(),{},f.deps);assert.equal(result.verified,true);assert.equal(f.calls.length,0);
});
test('Agent or piped confirmation is rejected; browser approval alone never confirms', async()=> {
  const f=fixture();await prepare(link(),{},f.deps);const path=[...f.files.keys()].find(path=>path.includes('.agentschat-binding-'));
  await assert.rejects(confirm(path,{...f.deps,tty:false}),/interactive/);
  await assert.rejects(confirm(path,{...f.deps,tty:true,question:async()=> 'yes'}),/did not approve/);
  assert.equal(f.calls.some(call=>call.path.endsWith('/confirm')),false);
});
test('operator exact confirmation preserves identity and verifies persisted ownership', async()=> {
  const f=fixture();await prepare(link(),{},f.deps);const path=[...f.files.keys()].find(path=>path.includes('.agentschat-binding-'));
  const result=await confirm(path,{...f.deps,tty:true,question:async()=>`BIND ${accountId} ${agentId}`,remove:path=>f.files.delete(path)});
  assert.equal(result.verified,true);assert.equal(result.agentId,agentId);assert.equal(f.files.has(path),false);
  const sent=f.calls.find(call=>call.path.endsWith('/confirm'));
  assert.equal(sent.body.authorization.purpose,'bind_account');assert.equal(sent.token,'PRIVATE_AGENT_BEARER');
});
test('wrong account scope and unverified ownership cannot become success', async()=> {
  const f=fixture();await prepare(link(),{},f.deps);const path=[...f.files.keys()].find(path=>path.includes('.agentschat-binding-'));
  const original=f.deps.http;f.deps.http=(...args)=>args[1].endsWith('/confirm')?{agent:{id:agentId,ownerUserId:'different'}}:original(...args);
  await assert.rejects(confirm(path,{...f.deps,tty:true,question:async()=>`BIND ${accountId} ${agentId}`,remove:()=>{}}),/not verified/);
  assert.equal(f.files.has(path),true);
});
test('operator commands quote file paths without putting secrets in arguments',()=> {
  const command=operatorCommand("C:\\owner's files\\binding.json","C:\\setup.mjs",true);
  assert.ok(command.includes("owner''s files"));assert.equal(command.includes(challengeToken),false);
});
