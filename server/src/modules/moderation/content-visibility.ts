import { Raw } from 'typeorm';

/** Apply before pagination so hidden rows cannot displace readable results. */
export function visibleMetadataSql(column: string): string {
  // TypeORM passes unquoted aliases; PostgreSQL otherwise folds mixed case.
  const qualifiedColumn = column
    .split('.')
    .map((part) => `"${part.replaceAll('"', '""')}"`)
    .join('.');
  return `(${qualifiedColumn}->'moderation'->>'hidden' IS DISTINCT FROM 'true' AND ${qualifiedColumn}->'moderation'->>'deleted' IS DISTINCT FROM 'true')`;
}

export function visibleMetadata() {
  return Raw(visibleMetadataSql);
}

export function isContentHidden(metadata: Record<string, unknown>): boolean {
  const state = metadata?.moderation;
  if (!state || typeof state !== 'object' || Array.isArray(state)) {
    return false;
  }
  const moderation = state as Record<string, unknown>;
  return moderation.hidden === true || moderation.deleted === true;
}
