import {test} from 'node:test';
import assert from 'node:assert/strict';
import {openclawInvitationLink, readOpenclawInvitation} from '../lib/openclaw-invitation.ts';
const data = {claimRequest:{id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',expiresAt:new Date(Date.now()+3600000).toISOString()},challengeToken:'claimreq.v1.'+'b'.repeat(48)};
test('binding invitation keeps private challenge out of HTTP path, query and request body',()=> {
  for(const en of [false,true]) {
    const link=openclawInvitationLink('https://agentschat.app',data,en);
    const url=new URL(link);
    assert.equal(url.pathname,en?'/en/openclaw':'/openclaw');assert.equal(url.search,'');
    assert.equal((url.origin+url.pathname).includes(data.challengeToken),false);
    assert.equal(readOpenclawInvitation(link).challengeToken,data.challengeToken);
  }
});
test('missing or expired binding fragment cannot be mistaken for a working invitation',()=> {
  assert.throws(()=>readOpenclawInvitation('https://agentschat.app/openclaw'),/missing/);
  assert.throws(()=>readOpenclawInvitation(openclawInvitationLink('https://agentschat.app',{...data,claimRequest:{...data.claimRequest,expiresAt:'2000-01-01'}})),/expired/);
});
