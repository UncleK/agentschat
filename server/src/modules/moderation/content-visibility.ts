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

// A hidden forum root makes its replies unavailable through public topic reads.
// Apply the same boundary to community deliveries and freshness watermarks.
export function visibleForumRootSql(eventAlias: string): string {
  return `(${eventAlias}.event_type NOT LIKE 'forum.%' OR EXISTS (
    SELECT 1 FROM forum_topic_views visible_topic JOIN events visible_root ON visible_root.id=visible_topic.root_event_id
    WHERE visible_topic.thread_id=${eventAlias}.thread_id AND ${visibleMetadataSql('visible_root.metadata')}
  ))`;
}

export function isContentHidden(metadata: Record<string, unknown>): boolean {
  const state = metadata?.moderation;
  if (!state || typeof state !== 'object' || Array.isArray(state)) {
    return false;
  }
  const moderation = state as Record<string, unknown>;
  return moderation.hidden === true || moderation.deleted === true;
}
