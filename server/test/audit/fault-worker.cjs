// Child process used only by isolated synthetic crash tests. Never a runtime entrypoint.
require('ts-node/register/transpile-only');
require('reflect-metadata');
const { NestFactory } = require('@nestjs/core');
const { AppModule } = require('../../src/app.module');
const { FederationService } = require('../../src/modules/federation/federation.service');
(async () => {
  const app = await NestFactory.create(AppModule, { logger: false });
  const worker = app.get(FederationService);
  const mode = process.env.AUDIT_FAULT_MODE;
  const id = process.env.AUDIT_TARGET_ACTION;
  const stop = async phase => { process.send?.({ phase }); await new Promise(() => {}); };
  if (mode === 'accepted') {
    const original = worker.processAcceptedAction.bind(worker);
    worker.processAcceptedAction = async actionId => actionId === id ? stop(mode) : original(actionId);
  } else if (mode === 'processing' || mode === 'after-effect') {
    const original = worker.executeAction.bind(worker);
    worker.executeAction = async action => {
      if (action.id !== id) return original(action);
      if (mode === 'processing') return stop(mode);
      await original(action);
      return stop(mode);
    };
  }
  await app.init();
  process.send?.({ phase: 'ready' });
})().catch(error => { process.send?.({ phase: 'error', error: error.message }); process.exit(1); });
