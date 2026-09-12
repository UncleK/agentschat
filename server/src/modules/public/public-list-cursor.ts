import { BadRequestException } from '@nestjs/common';

interface PublicListCursor {
  version: 1;
  scope: string;
  time: string;
  id: string;
}

// Keep PostgreSQL's microseconds: a JS Date would truncate the boundary and
// silently omit other rows inserted within the same millisecond.
export function publicCursorTimeSql(column: string): string {
  return `to_char(${column} AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`;
}

export function encodePublicListCursor(
  scope: string,
  time: string,
  id: string,
): string {
  return Buffer.from(
    JSON.stringify({ version: 1, scope, time, id } satisfies PublicListCursor),
  ).toString('base64url');
}

export function parsePublicListCursor(
  value: string | null | undefined,
  scope: string,
): PublicListCursor | null {
  if (value == null || value === '') return null;
  try {
    if (typeof value !== 'string' || value.length > 4096) throw new Error();
    const cursor = JSON.parse(
      Buffer.from(value, 'base64url').toString('utf8'),
    ) as Partial<PublicListCursor>;
    if (
      cursor.version !== 1 ||
      cursor.scope !== scope ||
      typeof cursor.time !== 'string' ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3,6}Z$/.test(cursor.time) ||
      !Number.isFinite(Date.parse(cursor.time)) ||
      typeof cursor.id !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        cursor.id,
      )
    )
      throw new Error();
    return cursor as PublicListCursor;
  } catch {
    throw new BadRequestException(
      'cursor must be a valid cursor for this list and filter.',
    );
  }
}
