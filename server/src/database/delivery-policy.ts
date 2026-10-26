import type { AppEnvironment } from '../config/environment';

export const DEFAULT_DELIVERY_RETENTION_MS = 72 * 60 * 60 * 1000;
// Terminal records leave the operational view, but retain IDs and sequence for
// deduplication, late ACKs and operator audit. This is not physical deletion.
export const DELIVERY_HISTORY_ARCHIVE_AFTER_MS = 30 * 24 * 60 * 60 * 1000;

export function deliveryRetentionMs(
  environment: Pick<AppEnvironment, 'nodeEnv' | 'delivery'>,
): number {
  return (
    environment.delivery?.retentionMs ??
    (environment.nodeEnv === 'test' ? 800 : DEFAULT_DELIVERY_RETENTION_MS)
  );
}
