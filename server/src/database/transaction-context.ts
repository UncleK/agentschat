import { AsyncLocalStorage } from 'node:async_hooks';
import { DataSource, EntityManager, ObjectLiteral, Repository } from 'typeorm';

interface Scope {
  manager: EntityManager;
  afterCommit: Array<() => void>;
}
const current = new AsyncLocalStorage<Scope>();
function activeScope(): Scope | undefined {
  const scope = current.getStore();
  const runner = scope?.manager.queryRunner;
  return runner?.isTransactionActive && !runner.isReleased ? scope : undefined;
}

export function transactionManager(database: DataSource): EntityManager {
  const manager = activeScope()?.manager;
  return manager?.connection === database ? manager : database.manager;
}

// Nest injects repositories once. A per-call proxy selects the current unit of
// work without mutating a shared repository/manager or affecting another request.
export function transactionalRepository<T extends ObjectLiteral>(
  repository: Repository<T>,
): Repository<T> {
  return new Proxy(repository, {
    get(target, property, receiver) {
      const scope = activeScope();
      if (scope && scope.manager.connection === target.manager?.connection) {
        if (property === 'manager') return scope.manager;
        if (property === 'queryRunner') return scope.manager.queryRunner;
      }
      return Reflect.get(target, property, receiver) as unknown;
    },
  });
}

export async function inTransaction<T>(
  database: DataSource,
  work: (manager: EntityManager) => Promise<T>,
): Promise<T> {
  const scope = activeScope();
  if (scope?.manager.connection === database) return work(scope.manager);
  const callbacks: Array<() => void> = [];
  const result = await database.transaction((manager) =>
    current.run({ manager, afterCommit: callbacks }, () => work(manager)),
  );
  for (const callback of callbacks)
    current.exit(() => {
      // Ephemeral notifications must never change an already committed result.
      try {
        callback();
      } catch {
        /* persistent outbox remains authoritative */
      }
    });
  return result;
}

export function afterCommit(callback: () => void): void {
  const scope = activeScope();
  if (scope) scope.afterCommit.push(callback);
  else callback();
}
