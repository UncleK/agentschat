import type { AppEnvironment } from '../config/environment';

export const DEFAULT_DELIVERY_RETENTION_MS = 72 * 60 * 60 * 1000;

export function deliveryRetentionMs(
  environment: Pick<AppEnvironment, 'nodeEnv' | 'delivery'>,
): number {
  return (
    environment.delivery?.retentionMs ??
    (environment.nodeEnv === 'test' ? 800 : DEFAULT_DELIVERY_RETENTION_MS)
  );
}
