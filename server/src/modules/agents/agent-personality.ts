export type AgentPersonalityLevel = 'low' | 'medium' | 'high';
export type AgentPersonalityCadence = 'slow' | 'normal' | 'fast';

export interface AgentPersonality {
  summary: string;
  warmth: AgentPersonalityLevel;
  curiosity: AgentPersonalityLevel;
  restraint: AgentPersonalityLevel;
  cadence: AgentPersonalityCadence;
  autoEvolve: boolean;
  lastDreamedAt: string | null;
}

function asRecord(value: unknown): Record<string, unknown> {
  return value != null && typeof value === 'object'
    ? (value as Record<string, unknown>)
    : {};
}

function optionalString(value: unknown): string | undefined {
  if (typeof value !== 'string') {
    return undefined;
  }
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : undefined;
}

function normalizeLevel(value: unknown): AgentPersonalityLevel | undefined {
  switch (value) {
    case 'low':
    case 'medium':
    case 'high':
      return value;
    default:
      return undefined;
  }
}

function normalizeCadence(value: unknown): AgentPersonalityCadence | undefined {
  switch (value) {
    case 'slow':
    case 'normal':
    case 'fast':
      return value;
    default:
      return undefined;
  }
}

function normalizeIsoTimestamp(value: unknown): string | null {
  const normalized = optionalString(value);
  if (!normalized) {
    return null;
  }
  const timestamp = Date.parse(normalized);
  if (Number.isNaN(timestamp)) {
    return null;
  }
  return new Date(timestamp).toISOString();
}

export function normalizeAgentPersonality(
  value: unknown,
): AgentPersonality | null {
  const source = asRecord(value);
  const summary = optionalString(source.summary)?.slice(0, 160);
  const warmth = normalizeLevel(source.warmth);
  const curiosity = normalizeLevel(source.curiosity);
  const restraint = normalizeLevel(source.restraint);
  const cadence = normalizeCadence(source.cadence);
  const autoEvolve =
    typeof source.autoEvolve === 'boolean' ? source.autoEvolve : undefined;
  const lastDreamedAt = normalizeIsoTimestamp(source.lastDreamedAt);

  if (
    !summary &&
    !warmth &&
    !curiosity &&
    !restraint &&
    !cadence &&
    autoEvolve === undefined &&
    lastDreamedAt === null
  ) {
    return null;
  }

  return {
    summary: summary ?? '',
    warmth: warmth ?? 'medium',
    curiosity: curiosity ?? 'medium',
    restraint: restraint ?? 'high',
    cadence: cadence ?? 'normal',
    autoEvolve: autoEvolve ?? false,
    lastDreamedAt,
  };
}

export function readAgentPersonality(
  metadata: Record<string, unknown> | null | undefined,
): AgentPersonality | null {
  if (!metadata) {
    return null;
  }
  return normalizeAgentPersonality(asRecord(metadata).personality);
}

export function mergeAgentPersonalityMetadata(
  metadata: Record<string, unknown>,
  personality: AgentPersonality | null,
): Record<string, unknown> {
  if (!personality) {
    return metadata;
  }

  return {
    ...metadata,
    personality,
  };
}
