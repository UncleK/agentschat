'use strict';
// Local extracted-method probe, not an HTTP/PostgreSQL integration test.
// Mock storage injects a concurrent committed change after the repository read.
// Mock repository ONLY records save() arguments: it never claims to emulate ORM.
// Resolve TypeScript via TYPESCRIPT_PATH or the global npm installation.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const tsPath = process.env.TYPESCRIPT_PATH || path.join(
  execFileSync(process.platform === 'win32' ? 'npm.cmd' : 'npm', ['root', '-g'], {encoding:'utf8'}).trim(),
  'typescript');
const ts = require(tsPath);
const source = fs.readFileSync(path.join(__dirname, 'avatar-method.ts'), 'utf8');
const compiled = ts.transpileModule(source, {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
const moduleObject = {exports:{}};
const context = {
  exports:moduleObject.exports, module:moduleObject, Buffer,
  NotFoundException:Error, ConflictException:Error, ForbiddenException:Error,
  AssetModerationStatus:{Rejected:'rejected'}, AVATAR_MAX_BYTES:1024,
  sanitizeAvatar:async bytes=>bytes,
};
vm.runInNewContext(compiled, context, {filename:'avatar-method.extracted.js'});
const {AvatarProbe} = moduleObject.exports;
async function observe(scenario) {
  const current = {
    id:'synthetic-agent', ownerType:scenario==='binding' ? 'self' : 'human',
    ownerUserId:scenario==='binding' ? null : 'synthetic-owner',
    avatarUrl:null,
    profileMetadata:{
      emergencyStopDmResponses:false,
      pendingAvatarUpload:{bucket:'synthetic',key:'agent-avatars/synthetic-agent/source.png',mimeType:'image/png'},
    },
  };
  let saved;
  const probe = new AvatarProbe();
  probe.agentRepository = {
    findOneBy:async()=>structuredClone(current),
    save:async entity=>{saved=structuredClone(entity);return entity;},
  };
  probe.assetStorageService = {
    headObject:async()=>{
      // Injection point: I/O awaits allow another request to commit a change.
      if(scenario==='stop') current.profileMetadata.emergencyStopDmResponses=true;
      if(scenario==='binding') {current.ownerType='human';current.ownerUserId='synthetic-new-owner';}
      return {byteSize:1,mimeType:'image/png'};
    },
    readObject:async()=>({body:Buffer.from([0])}), writeObject:async()=>{},
  };
  probe.imageModerationService={moderate:()=>({status:'approved',reason:null})};
  probe.readPendingAvatarUpload=metadata=>metadata.pendingAvatarUpload;
  probe.isOwnAvatarReference=()=>true; // not testing media authorization here
  probe.clearPendingAvatarUpload=metadata=>{const next={...metadata};delete next.pendingAvatarUpload;return next;};
  probe.withStoredAvatarMetadata=(metadata,value)=>({...metadata,avatarStorageBucket:value.bucket,avatarStorageKey:value.key,avatarMimeType:value.mimeType,avatarUpdatedAt:value.updatedAt});
  probe.buildAgentAvatarObjectKey=id=>`agent-avatars/${id}/verified.png`;
  probe.buildAgentAvatarPath=id=>`/api/v1/agents/${id}/avatar`;
  await probe.completeFederatedAgentAvatarUpload({id:current.id});
  if(scenario==='control') assert.equal(saved.profileMetadata.emergencyStopDmResponses,false);
  if(scenario==='stop') {
    assert.equal(current.profileMetadata.emergencyStopDmResponses,true);
    assert.equal(saved.profileMetadata.emergencyStopDmResponses,false);
  }
  if(scenario==='binding') {
    assert.equal(current.ownerType,'human'); assert.equal(saved.ownerType,'self');
    assert.equal(saved.ownerUserId,null);
  }
  return {
    scenario,
    currentAtSave:{ownerType:current.ownerType,ownerUserId:current.ownerUserId,emergencyStopDmResponses:current.profileMetadata.emergencyStopDmResponses},
    submittedToSave:{ownerType:saved.ownerType,ownerUserId:saved.ownerUserId,emergencyStopDmResponses:saved.profileMetadata.emergencyStopDmResponses},
    observationMatched:true,
  };
}
(async()=>{
  const results=[];
  for(const scenario of ['control','stop','binding']) results.push(await observe(scenario));
  console.log(JSON.stringify({commit:'7314f18a60843cc72c7566a817e7264fbe12fe4e',
    method:'extracted method, mocked dependencies; captured save payload only',
    postgresOrTypeormExecuted:false, results},null,2));
})().catch(error=>{console.error(error);process.exitCode=1;});
