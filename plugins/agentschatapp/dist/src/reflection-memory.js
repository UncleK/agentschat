import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { resolveSlotStateDir } from "./state.js";
const SCHEMA_VERSION = 1;
const MAX_HIGHLIGHTS_PER_DAY = 5;
const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
function emptyCounters() {
    return {
        considered7d: 0,
        replied7d: 0,
        skipped7d: 0,
        bySurface: {
            dm: { considered: 0, replied: 0, skipped: 0 },
            forum: { considered: 0, replied: 0, skipped: 0 },
            live: { considered: 0, replied: 0, skipped: 0 }
        }
    };
}
function createEmptyMemory() {
    return {
        schemaVersion: SCHEMA_VERSION,
        lastDreamedAt: null,
        dailyDigests: [],
        rollingSummary7d: "",
        interactionCounters: emptyCounters(),
        pendingTraitDrift: null,
        lastPersonalitySnapshot: null,
        recentInteractions: []
    };
}
function asRecord(value) {
    return value != null && typeof value === "object" ? value : {};
}
function normalizeOptionalString(value) {
    if (typeof value !== "string") {
        return undefined;
    }
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : undefined;
}
function normalizeIsoString(value) {
    const normalized = normalizeOptionalString(value);
    if (!normalized) {
        return null;
    }
    const timestamp = Date.parse(normalized);
    return Number.isNaN(timestamp) ? null : new Date(timestamp).toISOString();
}
function normalizeSurface(value) {
    switch (value) {
        case "dm":
        case "forum":
        case "live":
            return value;
        default:
            return undefined;
    }
}
function normalizeOutcome(value) {
    switch (value) {
        case "reply":
        case "skip":
            return value;
        default:
            return undefined;
    }
}
function normalizeReasonTag(value) {
    switch (value) {
        case "addressed":
        case "useful":
        case "novelty":
        case "low_signal":
        case "already_answered":
        case "cooldown":
        case "unsafe":
        case "not_interesting":
            return value;
        default:
            return undefined;
    }
}
function pruneWindow(items) {
    const cutoff = Date.now() - SEVEN_DAYS_MS;
    return items.filter((item) => {
        const timestamp = item.at ? Date.parse(item.at) : Number.NaN;
        return !Number.isNaN(timestamp) && timestamp >= cutoff;
    });
}
function digestDay(at) {
    return at.slice(0, 10);
}
function recomputeCounters(memory) {
    const counters = emptyCounters();
    for (const interaction of memory.recentInteractions) {
        counters.considered7d += 1;
        counters.bySurface[interaction.surface].considered += 1;
        if (interaction.outcome === "reply") {
            counters.replied7d += 1;
            counters.bySurface[interaction.surface].replied += 1;
        }
        else {
            counters.skipped7d += 1;
            counters.bySurface[interaction.surface].skipped += 1;
        }
    }
    memory.interactionCounters = counters;
}
function rebuildRollingSummary(memory) {
    const segments = memory.dailyDigests
        .slice(-7)
        .map((digest) => {
        const headline = `${digest.day}: considered ${digest.consideredCount}, replied ${digest.repliedCount}, skipped ${digest.skippedCount}`;
        const highlights = digest.highlights.length > 0 ? ` Highlights: ${digest.highlights.join(" | ")}` : "";
        return `${headline}.${highlights}`.trim();
    });
    memory.rollingSummary7d = segments.join("\n");
}
function normalizeDailyDigest(value) {
    const source = asRecord(value);
    const day = normalizeOptionalString(source.day);
    if (!day) {
        return undefined;
    }
    const highlights = Array.isArray(source.highlights)
        ? source.highlights
            .filter((entry) => typeof entry === "string")
            .map((entry) => String(entry).trim())
            .filter((entry) => entry.length > 0)
            .slice(0, MAX_HIGHLIGHTS_PER_DAY)
        : [];
    return {
        day,
        consideredCount: typeof source.consideredCount === "number" ? source.consideredCount : 0,
        repliedCount: typeof source.repliedCount === "number" ? source.repliedCount : 0,
        skippedCount: typeof source.skippedCount === "number" ? source.skippedCount : 0,
        highlights
    };
}
function normalizeInteraction(value) {
    const source = asRecord(value);
    const at = normalizeIsoString(source.at);
    const surface = normalizeSurface(source.surface);
    const outcome = normalizeOutcome(source.outcome);
    const reasonTag = normalizeReasonTag(source.reasonTag);
    const threadKey = normalizeOptionalString(source.threadKey);
    const summary = normalizeOptionalString(source.summary);
    if (!at || !surface || !outcome || !reasonTag || !threadKey || !summary) {
        return undefined;
    }
    return { at, surface, outcome, reasonTag, threadKey, summary: summary.slice(0, 220) };
}
export function resolveReflectionMemoryPath(slot, store) {
    const slotDir = resolveSlotStateDir(slot, store);
    mkdirSync(slotDir, { recursive: true });
    return join(slotDir, "reflection-memory.json");
}
export function loadReflectionMemory(slot, store) {
    const path = resolveReflectionMemoryPath(slot, store);
    if (!existsSync(path)) {
        return createEmptyMemory();
    }
    try {
        const parsed = asRecord(JSON.parse(readFileSync(path, "utf8")));
        const normalized = {
            schemaVersion: SCHEMA_VERSION,
            lastDreamedAt: normalizeIsoString(parsed.lastDreamedAt),
            dailyDigests: Array.isArray(parsed.dailyDigests)
                ? parsed.dailyDigests.map(normalizeDailyDigest).filter((entry) => Boolean(entry)).slice(-7)
                : [],
            rollingSummary7d: normalizeOptionalString(parsed.rollingSummary7d) ?? "",
            interactionCounters: emptyCounters(),
            pendingTraitDrift: (() => {
                const drift = asRecord(parsed.pendingTraitDrift);
                const trait = normalizeOptionalString(drift.trait);
                const at = normalizeIsoString(drift.at);
                const from = normalizeOptionalString(drift.from);
                const to = normalizeOptionalString(drift.to);
                if (!trait || !at || !from || !to) {
                    return null;
                }
                if (trait !== "warmth" && trait !== "curiosity" && trait !== "restraint" && trait !== "cadence") {
                    return null;
                }
                return {
                    trait,
                    from,
                    to,
                    at
                };
            })(),
            lastPersonalitySnapshot: parsed.lastPersonalitySnapshot != null ? parsed.lastPersonalitySnapshot : null,
            recentInteractions: Array.isArray(parsed.recentInteractions)
                ? pruneWindow(parsed.recentInteractions.map(normalizeInteraction).filter((entry) => Boolean(entry)))
                : []
        };
        recomputeCounters(normalized);
        rebuildRollingSummary(normalized);
        return normalized;
    }
    catch {
        return createEmptyMemory();
    }
}
export function saveReflectionMemory(slot, store, memory) {
    const normalized = pruneReflectionMemory(memory);
    const path = resolveReflectionMemoryPath(slot, store);
    writeFileSync(path, JSON.stringify(normalized, null, 2), "utf8");
}
export function pruneReflectionMemory(memory) {
    const next = {
        ...memory,
        dailyDigests: memory.dailyDigests.slice(-7),
        recentInteractions: pruneWindow(memory.recentInteractions).slice(-200)
    };
    recomputeCounters(next);
    rebuildRollingSummary(next);
    return next;
}
export function recordReflectionInteraction(memory, interaction) {
    const next = pruneReflectionMemory({
        ...memory,
        recentInteractions: [...memory.recentInteractions, interaction]
    });
    const day = digestDay(interaction.at);
    const existing = next.dailyDigests.find((digest) => digest.day === day);
    if (existing) {
        existing.consideredCount += 1;
        if (interaction.outcome === "reply") {
            existing.repliedCount += 1;
        }
        else {
            existing.skippedCount += 1;
        }
        if (existing.highlights.length < MAX_HIGHLIGHTS_PER_DAY) {
            existing.highlights.push(interaction.summary);
        }
    }
    else {
        next.dailyDigests.push({
            day,
            consideredCount: 1,
            repliedCount: interaction.outcome === "reply" ? 1 : 0,
            skippedCount: interaction.outcome === "skip" ? 1 : 0,
            highlights: [interaction.summary]
        });
    }
    next.dailyDigests = next.dailyDigests.slice(-7);
    recomputeCounters(next);
    rebuildRollingSummary(next);
    return next;
}
export function countRecentThreadReplies(memory, threadKey, withinMs, now = Date.now()) {
    const cutoff = now - withinMs;
    return memory.recentInteractions.filter((interaction) => {
        const timestamp = Date.parse(interaction.at);
        return interaction.threadKey === threadKey
            && interaction.outcome === "reply"
            && !Number.isNaN(timestamp)
            && timestamp >= cutoff;
    }).length;
}
export function wasTraitChangedRecently(memory, trait, withinMs) {
    if (!memory.pendingTraitDrift || memory.pendingTraitDrift.trait !== trait) {
        return false;
    }
    const timestamp = Date.parse(memory.pendingTraitDrift.at);
    return !Number.isNaN(timestamp) && (Date.now() - timestamp) < withinMs;
}
