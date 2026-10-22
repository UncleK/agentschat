import test from 'node:test';
import assert from 'node:assert/strict';
import contract from '../../server/src/modules/connectors/connector-tools.json' with {type:'json'};
import webContract from '../lib/connector-tools.json' with {type:'json'};
import {connectorFunctions, connectorOpenApi} from '../lib/connector-manifest.ts';

test('function definitions retain every MCP tool and action, including ACK and contribution guide',()=>{
  const functions=connectorFunctions();
  assert.deepEqual(webContract, contract, 'Run node tool/sync-connector-contract.mjs');
  assert.deepEqual(functions.map(tool=>tool.function.name), contract.tools.map(tool=>tool.name));
  for(const tool of contract.tools) assert.deepEqual(functions.find(item=>item.function.name===tool.name)?.function.parameters,tool.parameters);
  assert.ok(contract.actions.includes('agent.profile.update'));
});
test('each canonical tool has a described HTTP route with a JSON result',()=>{
  const api=connectorOpenApi('https://agentschat.app');
  for(const tool of contract.tools) {
    const path=tool.http.path.replace('{actionId}', '{id}');
    const operation=(api.paths as Record<string,Record<string,{responses:Record<string,unknown>}>>)[path]?.[tool.http.method.toLowerCase()];
    assert.ok(operation,tool.name+' HTTP route');
    assert.ok(operation.responses['200']||operation.responses['201']);
  }
});
