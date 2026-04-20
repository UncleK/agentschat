import type { AgentsChatActivityLevel, AgentsChatState } from "./types.js";

export type AgentsChatPersonalityLevel = "low" | "medium" | "high";
export type AgentsChatPersonalityCadence = "slow" | "normal" | "fast";
export type ConversationalSurface = "dm" | "forum" | "live";

export type AgentsChatPersonality = {
  summary: string;
  warmth: AgentsChatPersonalityLevel;
  curiosity: AgentsChatPersonalityLevel;
  restraint: AgentsChatPersonalityLevel;
  cadence: AgentsChatPersonalityCadence;
  autoEvolve: boolean;
  lastDreamedAt: string | null;
};

const DEFAULT_SUMMARY = "Warm, selective, and context-aware.";

export const DEFAULT_AGENT_PERSONALITY: AgentsChatPersonality = Object.freeze({
  summary: DEFAULT_SUMMARY,
  warmth: "medium",
  curiosity: "medium",
  restraint: "high",
  cadence: "normal",
  autoEvolve: true,
  lastDreamedAt: null
});

function asRecord(value: unknown): Record<string, unknown> {
  return value != null && typeof value === "object" ? (value as Record<string, unknown>) : {};
}

function normalizeOptionalString(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function normalizeLevel(value: unknown): AgentsChatPersonalityLevel | undefined {
  switch (value) {
    case "low":
    case "medium":
    case "high":
      return value;
    default:
      return undefined;
  }
}

function normalizeCadence(value: unknown): AgentsChatPersonalityCadence | undefined {
  switch (value) {
    case "slow":
    case "normal":
    case "fast":
      return value;
    default:
      return undefined;
  }
}

function normalizeIsoString(value: unknown): string | null {
  const normalized = normalizeOptionalString(value);
  if (!normalized) {
    return null;
  }
  const timestamp = Date.parse(normalized);
  return Number.isNaN(timestamp) ? null : new Date(timestamp).toISOString();
}

export function clonePersonality(
  personality: AgentsChatPersonality = DEFAULT_AGENT_PERSONALITY
): AgentsChatPersonality {
  return {
    summary: personality.summary,
    warmth: personality.warmth,
    curiosity: personality.curiosity,
    restraint: personality.restraint,
    cadence: personality.cadence,
    autoEvolve: personality.autoEvolve,
    lastDreamedAt: personality.lastDreamedAt
  };
}

export function normalizePersonality(
  value: unknown,
  fallback: AgentsChatPersonality = DEFAULT_AGENT_PERSONALITY
): AgentsChatPersonality {
  const source = asRecord(value);
  return {
    summary: normalizeOptionalString(source.summary)?.slice(0, 160) ?? fallback.summary,
    warmth: normalizeLevel(source.warmth) ?? fallback.warmth,
    curiosity: normalizeLevel(source.curiosity) ?? fallback.curiosity,
    restraint: normalizeLevel(source.restraint) ?? fallback.restraint,
    cadence: normalizeCadence(source.cadence) ?? fallback.cadence,
    autoEvolve: typeof source.autoEvolve === "boolean" ? source.autoEvolve : fallback.autoEvolve,
    lastDreamedAt: normalizeIsoString(source.lastDreamedAt)
  };
}

export function personalityToPayload(
  personality: AgentsChatPersonality | null | undefined
): Record<string, unknown> | undefined {
  if (!personality) {
    return undefined;
  }
  return {
    summary: personality.summary,
    warmth: personality.warmth,
    curiosity: personality.curiosity,
    restraint: personality.restraint,
    cadence: personality.cadence,
    autoEvolve: personality.autoEvolve,
    lastDreamedAt: personality.lastDreamedAt
  };
}

export function resolveStatePersonality(state: AgentsChatState): AgentsChatPersonality {
  return normalizePersonality(state.personality ?? undefined);
}

export function summarizePersonality(personality: AgentsChatPersonality): string {
  return [
    `summary=${personality.summary || DEFAULT_SUMMARY}`,
    `warmth=${personality.warmth}`,
    `curiosity=${personality.curiosity}`,
    `restraint=${personality.restraint}`,
    `cadence=${personality.cadence}`
  ].join(", ");
}

function curiosityThresholdOffset(value: AgentsChatPersonalityLevel): number {
  switch (value) {
    case "high":
      return -1;
    case "low":
      return 1;
    default:
      return 0;
  }
}

function restraintThresholdOffset(value: AgentsChatPersonalityLevel): number {
  switch (value) {
    case "high":
      return 1;
    case "low":
      return -1;
    default:
      return 0;
  }
}

export function computeReplyThreshold(
  activityLevel: AgentsChatActivityLevel,
  personality: AgentsChatPersonality
): number {
  const baseThreshold = activityLevel === "low" ? 5 : activityLevel === "high" ? 2 : 3;
  const adjusted =
    baseThreshold
    + curiosityThresholdOffset(personality.curiosity)
    + restraintThresholdOffset(personality.restraint);
  return Math.max(1, Math.min(6, adjusted));
}

export function cadenceRangeMs(
  surface: ConversationalSurface,
  cadence: AgentsChatPersonalityCadence
): { minMs: number; maxMs: number } {
  if (surface === "dm") {
    switch (cadence) {
      case "slow":
        return { minMs: 25_000, maxMs: 60_000 };
      case "fast":
        return { minMs: 3_000, maxMs: 10_000 };
      default:
        return { minMs: 10_000, maxMs: 25_000 };
    }
  }
  if (surface === "forum") {
    switch (cadence) {
      case "slow":
        return { minMs: 120_000, maxMs: 300_000 };
      case "fast":
        return { minMs: 30_000, maxMs: 60_000 };
      default:
        return { minMs: 60_000, maxMs: 120_000 };
    }
  }
  switch (cadence) {
    case "slow":
      return { minMs: 20_000, maxMs: 40_000 };
    case "fast":
      return { minMs: 4_000, maxMs: 10_000 };
    default:
      return { minMs: 10_000, maxMs: 20_000 };
  }
}

export function randomDebounceMs(
  surface: ConversationalSurface,
  personality: AgentsChatPersonality
): number {
  const range = cadenceRangeMs(surface, personality.cadence);
  if (range.maxMs <= range.minMs) {
    return range.minMs;
  }
  return range.minMs + Math.floor(Math.random() * (range.maxMs - range.minMs + 1));
}

export function activityPenaltyMultiplier(activityLevel: AgentsChatActivityLevel): number {
  switch (activityLevel) {
    case "low":
      return 2;
    case "high":
      return 1;
    default:
      return 1.5;
  }
}

export function buildFallbackPersonalitySummary(input: {
  displayName?: string;
  bio?: string;
  profileTags?: string[];
}): string {
  const bio = normalizeOptionalString(input.bio);
  if (bio) {
    return bio.slice(0, 160);
  }
  const tags = (input.profileTags ?? []).map((entry) => entry.trim()).filter((entry) => entry.length > 0);
  if (tags.length > 0) {
    return `${input.displayName ?? "Agent"} is ${tags.slice(0, 3).join(", ")}.`;
  }
  const displayName = normalizeOptionalString(input.displayName) ?? "This agent";
  return `${displayName} is warm, selective, and context-aware.`;
}

export function diffPersonalityTraits(
  previous: AgentsChatPersonality,
  next: AgentsChatPersonality
): Array<"warmth" | "curiosity" | "restraint" | "cadence"> {
  const changed: Array<"warmth" | "curiosity" | "restraint" | "cadence"> = [];
  if (previous.warmth !== next.warmth) {
    changed.push("warmth");
  }
  if (previous.curiosity !== next.curiosity) {
    changed.push("curiosity");
  }
  if (previous.restraint !== next.restraint) {
    changed.push("restraint");
  }
  if (previous.cadence !== next.cadence) {
    changed.push("cadence");
  }
  return changed;
}

function clampIndexedStep<T extends string>(
  order: readonly T[],
  previous: T,
  next: T
): T {
  const previousIndex = order.indexOf(previous);
  const nextIndex = order.indexOf(next);
  if (previousIndex < 0 || nextIndex < 0) {
    return previous;
  }
  if (Math.abs(nextIndex - previousIndex) <= 1) {
    return next;
  }
  return order[previousIndex + Math.sign(nextIndex - previousIndex)];
}

export function clampTraitDrift(
  previous: AgentsChatPersonality,
  next: AgentsChatPersonality
): AgentsChatPersonality {
  return {
    ...next,
    warmth: clampIndexedStep(["low", "medium", "high"], previous.warmth, next.warmth),
    curiosity: clampIndexedStep(["low", "medium", "high"], previous.curiosity, next.curiosity),
    restraint: clampIndexedStep(["low", "medium", "high"], previous.restraint, next.restraint),
    cadence: clampIndexedStep(["slow", "normal", "fast"], previous.cadence, next.cadence)
  };
}
