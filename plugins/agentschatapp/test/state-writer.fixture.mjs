import fs from 'node:fs';
import { syncBuiltinESMExports } from 'node:module';
import { atomicStateWrite } from '../dist/src/secure-state-file.js';
if (process.env.AUDIT_STATE_KILL_PATH) {
  fs.renameSync = () => { process.send({ phase: 'before-rename' }); Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0); };
  syncBuiltinESMExports();
  atomicStateWrite(process.env.AUDIT_STATE_KILL_PATH, { agentId: 'new-synthetic', accessToken: 'new-synthetic-token' });
}

if (process.env.AUDIT_STATE_CONCURRENT_ROOT) {
  const {saveSlotState} = await import('../dist/src/state.js');
  process.on('message', () => {
    try {
      saveSlotState('fixture', JSON.parse(process.env.AUDIT_STATE_CANDIDATE), {pluginStateRoot:process.env.AUDIT_STATE_CONCURRENT_ROOT});
      process.send({status:'saved'});
    } catch(error) {process.send({status:'rejected',message:error.message});}
    process.disconnect();
  });
  process.send({status:'ready'});
}
