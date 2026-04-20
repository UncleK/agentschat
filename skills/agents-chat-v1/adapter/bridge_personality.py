"""Shared personality and reflection-memory helpers for the legacy bridge."""

from __future__ import annotations

import json
import random
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

DEFAULT_AGENT_PERSONALITY: dict[str, Any] = {
    "summary": "Warm, selective, and context-aware.",
    "warmth": "medium",
    "curiosity": "medium",
    "restraint": "high",
    "cadence": "normal",
    "autoEvolve": True,
    "lastDreamedAt": None,
}
PERSONALITY_LEVEL_ORDER = ("low", "medium", "high")
PERSONALITY_CADENCE_ORDER = ("slow", "normal", "fast")
SEVEN_DAYS_SECONDS = 7 * 24 * 60 * 60
MAX_DAILY_HIGHLIGHTS = 5
MAX_RECENT_INTERACTIONS = 200
MAX_SUMMARY_CHARS = 160

LOW_SIGNAL_PATTERN = re.compile(r"^:[a-z0-9_+\-]+:$", re.IGNORECASE)
HELP_SIGNAL_PATTERN = re.compile(
    r"\b(help|why|how|should|could|can you|need|stuck|issue|problem|debate|disagree)\b",
    re.IGNORECASE,
)
LOW_SIGNAL_ACK_PATTERN = re.compile(
    r"^(ok|okay|k|kk|lol|hi|hey|yo|nice|cool|sure|thanks|thx|\u6536\u5230|\u597d\u7684|\u55EF\u54FC)$",
    re.IGNORECASE,
)
REASON_TAGS = {
    "addressed",
    "useful",
    "novelty",
    "low_signal",
    "already_answered",
    "cooldown",
    "unsafe",
    "not_interesting",
}


def as_record(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def normalize_optional_string(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = value.strip()
    return normalized or None


def parse_iso_seconds(value: Any) -> float | None:
    normalized = normalize_optional_string(value)
    if not normalized:
        return None
    candidate = normalized.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(candidate)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).timestamp()


def normalize_iso_string(value: Any) -> str | None:
    seconds = parse_iso_seconds(value)
    if seconds is None:
        return None
    return datetime.fromtimestamp(seconds, tz=timezone.utc).isoformat(
        timespec="milliseconds"
    ).replace("+00:00", "Z")


def normalize_personality(
    value: Any,
    fallback: dict[str, Any] | None = None,
) -> dict[str, Any]:
    source = as_record(value)
    base = dict(DEFAULT_AGENT_PERSONALITY)
    if fallback:
        base.update(fallback)

    summary = normalize_optional_string(source.get("summary"))
    if summary:
        base["summary"] = summary[:MAX_SUMMARY_CHARS]

    for trait in ("warmth", "curiosity", "restraint"):
        trait_value = normalize_optional_string(source.get(trait))
        if trait_value in PERSONALITY_LEVEL_ORDER:
            base[trait] = trait_value

    cadence = normalize_optional_string(source.get("cadence"))
    if cadence in PERSONALITY_CADENCE_ORDER:
        base["cadence"] = cadence

    if isinstance(source.get("autoEvolve"), bool):
        base["autoEvolve"] = source["autoEvolve"]

    base["lastDreamedAt"] = normalize_iso_string(source.get("lastDreamedAt"))
    return base


def personality_to_payload(personality: dict[str, Any] | None) -> dict[str, Any] | None:
    if not personality:
        return None
    return {
        "summary": personality.get("summary", ""),
        "warmth": personality.get("warmth", "medium"),
        "curiosity": personality.get("curiosity", "medium"),
        "restraint": personality.get("restraint", "high"),
        "cadence": personality.get("cadence", "normal"),
        "autoEvolve": bool(personality.get("autoEvolve")),
        "lastDreamedAt": normalize_iso_string(personality.get("lastDreamedAt")),
    }


def build_fallback_personality_summary(state: dict[str, Any]) -> str:
    bio = normalize_optional_string(state.get("bio"))
    if bio:
        return bio[:MAX_SUMMARY_CHARS]

    tags = [
        entry.strip()
        for entry in state.get("profileTags", [])
        if isinstance(entry, str) and entry.strip()
    ]
    display_name = normalize_optional_string(state.get("displayName")) or "This agent"
    if tags:
        return f"{display_name} is {', '.join(tags[:3])}."[:MAX_SUMMARY_CHARS]
    return f"{display_name} is warm, selective, and context-aware."[
        :MAX_SUMMARY_CHARS
    ]


def compute_reply_threshold(activity_level: str, personality: dict[str, Any]) -> int:
    base = 5 if activity_level == "low" else 2 if activity_level == "high" else 3
    curiosity = personality.get("curiosity")
    restraint = personality.get("restraint")
    if curiosity == "high":
        base -= 1
    elif curiosity == "low":
        base += 1
    if restraint == "high":
        base += 1
    elif restraint == "low":
        base -= 1
    return max(1, min(6, base))


def activity_penalty_multiplier(activity_level: str) -> float:
    if activity_level == "low":
        return 2.0
    if activity_level == "high":
        return 1.0
    return 1.5


def random_debounce_seconds(surface: str, personality: dict[str, Any]) -> float:
    cadence = personality.get("cadence", "normal")
    ranges = {
        ("dm", "slow"): (25, 60),
        ("dm", "normal"): (10, 25),
        ("dm", "fast"): (3, 10),
        ("forum", "slow"): (120, 300),
        ("forum", "normal"): (60, 120),
        ("forum", "fast"): (30, 60),
        ("live", "slow"): (20, 40),
        ("live", "normal"): (10, 20),
        ("live", "fast"): (4, 10),
    }
    lower, upper = ranges.get((surface, cadence), ranges[(surface, "normal")])
    return random.uniform(lower, upper)


def trim_text(value: str, max_chars: int) -> str:
    normalized = value.strip()
    if max_chars <= 0 or len(normalized) <= max_chars:
        return normalized
    if max_chars <= 3:
        return normalized[:max_chars]
    return normalized[: max_chars - 3].rstrip() + "..."


def detect_low_signal(content: str) -> bool:
    normalized = content.strip().lower()
    if not normalized:
        return True
    if LOW_SIGNAL_PATTERN.match(normalized) or LOW_SIGNAL_ACK_PATTERN.match(normalized):
        return True
    return len(normalized) < 8 and "?" not in normalized and "\uFF1F" not in normalized


def mentions_agent(content: str, state: dict[str, Any]) -> bool:
    normalized = content.lower()
    handle = normalize_optional_string(state.get("agentHandle"))
    candidates = [
        normalize_optional_string(state.get("displayName")),
        handle,
        f"@{handle}" if handle else None,
    ]
    return any(candidate and candidate.lower() in normalized for candidate in candidates)


def has_question(content: str) -> bool:
    return "?" in content or "\uFF1F" in content


def has_help_signal(content: str) -> bool:
    return bool(HELP_SIGNAL_PATTERN.search(content)) or any(
        signal in content
        for signal in (
            "\u8BF7\u95EE",
            "\u5982\u4F55",
            "\u4E3A\u4EC0\u4E48",
            "\u95EE\u9898",
            "\u9700\u8981",
            "\u5361\u4F4F",
            "\u8FA9\u8BBA",
            "\u4E0D\u540C\u610F",
        )
    )


def clamp_indexed_step(order: tuple[str, ...], previous: str, next_value: str) -> str:
    try:
        previous_index = order.index(previous)
        next_index = order.index(next_value)
    except ValueError:
        return previous
    if abs(next_index - previous_index) <= 1:
        return next_value
    return order[previous_index + (1 if next_index > previous_index else -1)]


def diff_personality_traits(
    previous: dict[str, Any],
    next_value: dict[str, Any],
) -> list[str]:
    changed: list[str] = []
    for trait in ("warmth", "curiosity", "restraint", "cadence"):
        if previous.get(trait) != next_value.get(trait):
            changed.append(trait)
    return changed


def clamp_trait_drift(
    previous: dict[str, Any],
    next_value: dict[str, Any],
) -> dict[str, Any]:
    output = dict(next_value)
    output["warmth"] = clamp_indexed_step(
        PERSONALITY_LEVEL_ORDER,
        str(previous.get("warmth", "medium")),
        str(next_value.get("warmth", previous.get("warmth", "medium"))),
    )
    output["curiosity"] = clamp_indexed_step(
        PERSONALITY_LEVEL_ORDER,
        str(previous.get("curiosity", "medium")),
        str(next_value.get("curiosity", previous.get("curiosity", "medium"))),
    )
    output["restraint"] = clamp_indexed_step(
        PERSONALITY_LEVEL_ORDER,
        str(previous.get("restraint", "high")),
        str(next_value.get("restraint", previous.get("restraint", "high"))),
    )
    output["cadence"] = clamp_indexed_step(
        PERSONALITY_CADENCE_ORDER,
        str(previous.get("cadence", "normal")),
        str(next_value.get("cadence", previous.get("cadence", "normal"))),
    )
    return output


def limit_messages(
    messages: list[dict[str, Any]],
    max_count: int,
    max_chars: int,
    content_getter: Callable[[dict[str, Any]], str],
) -> list[dict[str, Any]]:
    filtered = messages[-max_count:]
    selected: list[dict[str, Any]] = []
    remaining_chars = max_chars
    for message in reversed(filtered):
        content = content_getter(message)
        cost = max(len(content), 1)
        if selected and remaining_chars - cost < 0:
            break
        remaining_chars -= cost
        selected.append(message)
    selected.reverse()
    return selected


def newer_external_activity_exists(
    *,
    self_agent_id: str,
    original_actor_id: str | None,
    since_seconds: float | None,
    entries: list[dict[str, Any]],
    actor_resolver: Callable[[dict[str, Any]], tuple[str | None, str | None, float | None]],
) -> bool:
    if since_seconds is None:
        return False
    for entry in entries:
        actor_id, actor_type, occurred_at = actor_resolver(entry)
        if occurred_at is None or occurred_at <= since_seconds:
            continue
        if actor_type == "agent" and actor_id == self_agent_id:
            continue
        if original_actor_id and actor_id == original_actor_id:
            continue
        return True
    return False


def empty_reflection_counters() -> dict[str, Any]:
    return {
        "considered7d": 0,
        "replied7d": 0,
        "skipped7d": 0,
        "bySurface": {
            "dm": {"considered": 0, "replied": 0, "skipped": 0},
            "forum": {"considered": 0, "replied": 0, "skipped": 0},
            "live": {"considered": 0, "replied": 0, "skipped": 0},
        },
    }


def empty_reflection_memory() -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "lastDreamedAt": None,
        "dailyDigests": [],
        "rollingSummary7d": "",
        "interactionCounters": empty_reflection_counters(),
        "pendingTraitDrift": None,
        "lastPersonalitySnapshot": None,
        "recentInteractions": [],
    }


def reflection_memory_path(state_dir: Path) -> Path:
    return state_dir / "reflection-memory.json"


def _prune_recent_interactions(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    cutoff = time.time() - SEVEN_DAYS_SECONDS
    output: list[dict[str, Any]] = []
    for item in items:
        timestamp = parse_iso_seconds(item.get("at"))
        if timestamp is None or timestamp < cutoff:
            continue
        output.append(item)
    return output[-MAX_RECENT_INTERACTIONS:]


def _recompute_counters(memory: dict[str, Any]) -> None:
    counters = empty_reflection_counters()
    for interaction in memory.get("recentInteractions", []):
        surface = interaction.get("surface")
        if surface not in {"dm", "forum", "live"}:
            continue
        counters["considered7d"] += 1
        counters["bySurface"][surface]["considered"] += 1
        if interaction.get("outcome") == "reply":
            counters["replied7d"] += 1
            counters["bySurface"][surface]["replied"] += 1
        else:
            counters["skipped7d"] += 1
            counters["bySurface"][surface]["skipped"] += 1
    memory["interactionCounters"] = counters


def _rebuild_daily_digests(memory: dict[str, Any]) -> None:
    buckets: dict[str, dict[str, Any]] = {}
    for interaction in memory.get("recentInteractions", []):
        day = str(interaction.get("at", ""))[:10]
        if not day:
            continue
        digest = buckets.setdefault(
            day,
            {
                "day": day,
                "consideredCount": 0,
                "repliedCount": 0,
                "skippedCount": 0,
                "highlights": [],
            },
        )
        digest["consideredCount"] += 1
        if interaction.get("outcome") == "reply":
            digest["repliedCount"] += 1
        else:
            digest["skippedCount"] += 1
        summary = normalize_optional_string(interaction.get("summary"))
        if summary and len(digest["highlights"]) < MAX_DAILY_HIGHLIGHTS:
            digest["highlights"].append(summary[:220])
    memory["dailyDigests"] = sorted(buckets.values(), key=lambda item: item["day"])[-7:]


def _rebuild_rolling_summary(memory: dict[str, Any]) -> None:
    segments: list[str] = []
    for digest in memory.get("dailyDigests", [])[-7:]:
        headline = (
            f"{digest['day']}: considered {digest['consideredCount']}, "
            f"replied {digest['repliedCount']}, skipped {digest['skippedCount']}"
        )
        highlights = digest.get("highlights") or []
        if highlights:
            headline += f". Highlights: {' | '.join(highlights)}"
        segments.append(headline)
    memory["rollingSummary7d"] = "\n".join(segments)


def load_reflection_memory(state_dir: Path) -> dict[str, Any]:
    path = reflection_memory_path(state_dir)
    if not path.exists():
        return empty_reflection_memory()
    try:
        parsed = as_record(json.loads(path.read_text(encoding="utf-8")))
    except (OSError, json.JSONDecodeError):
        return empty_reflection_memory()

    memory = empty_reflection_memory()
    memory["lastDreamedAt"] = normalize_iso_string(parsed.get("lastDreamedAt"))
    memory["pendingTraitDrift"] = (
        parsed.get("pendingTraitDrift")
        if isinstance(parsed.get("pendingTraitDrift"), dict)
        else None
    )
    if isinstance(parsed.get("lastPersonalitySnapshot"), dict):
        memory["lastPersonalitySnapshot"] = normalize_personality(
            parsed["lastPersonalitySnapshot"]
        )
    memory["recentInteractions"] = _prune_recent_interactions(
        [
            as_record(item)
            for item in parsed.get("recentInteractions", [])
            if isinstance(item, dict)
        ]
    )
    _recompute_counters(memory)
    _rebuild_daily_digests(memory)
    _rebuild_rolling_summary(memory)
    return memory


def save_reflection_memory(state_dir: Path, memory: dict[str, Any]) -> None:
    normalized = dict(memory)
    normalized["recentInteractions"] = _prune_recent_interactions(
        [
            as_record(item)
            for item in normalized.get("recentInteractions", [])
            if isinstance(item, dict)
        ]
    )
    _recompute_counters(normalized)
    _rebuild_daily_digests(normalized)
    _rebuild_rolling_summary(normalized)
    reflection_memory_path(state_dir).write_text(
        json.dumps(normalized, indent=2, sort_keys=True),
        encoding="utf-8",
    )


def record_reflection_interaction(
    memory: dict[str, Any],
    *,
    at: str,
    surface: str,
    thread_key: str,
    outcome: str,
    reason_tag: str,
    summary: str,
) -> dict[str, Any]:
    next_memory = dict(memory)
    next_memory["recentInteractions"] = [
        *memory.get("recentInteractions", []),
        {
            "at": at,
            "surface": surface,
            "threadKey": thread_key,
            "outcome": outcome,
            "reasonTag": reason_tag,
            "summary": trim_text(summary, 220),
        },
    ]
    return next_memory


def count_recent_thread_replies(
    memory: dict[str, Any],
    thread_key: str,
    within_seconds: int,
) -> int:
    cutoff = time.time() - within_seconds
    count = 0
    for interaction in memory.get("recentInteractions", []):
        timestamp = parse_iso_seconds(interaction.get("at"))
        if timestamp is None or timestamp < cutoff:
            continue
        if interaction.get("threadKey") != thread_key:
            continue
        if interaction.get("outcome") != "reply":
            continue
        count += 1
    return count


def was_trait_changed_recently(
    memory: dict[str, Any],
    trait: str,
    within_seconds: int,
) -> bool:
    drift = as_record(memory.get("pendingTraitDrift"))
    if drift.get("trait") != trait:
        return False
    timestamp = parse_iso_seconds(drift.get("at"))
    return timestamp is not None and (time.time() - timestamp) < within_seconds


def build_interaction_summary(
    *,
    surface: str,
    outcome: str,
    sender_name: str | None,
    content: str,
    reason_tag: str,
) -> str:
    sender = normalize_optional_string(sender_name) or "someone"
    verb = "Replied to" if outcome == "reply" else "Skipped"
    return (
        f"{verb} {surface} from {sender}: "
        f"{trim_text(content or '[empty]', 96)} ({reason_tag})."
    )


def parse_decision_envelope(raw_text: str, max_chars: int = 4000) -> dict[str, Any]:
    normalized = raw_text.strip()
    if not normalized or normalized.upper() == "NO_REPLY":
        return {
            "decision": "skip",
            "reasonTag": "not_interesting",
            "replyText": "",
        }

    match = re.search(r"\{[\s\S]*\}", normalized)
    parsed: dict[str, Any] = {}
    if match:
        try:
            parsed = as_record(json.loads(match.group(0)))
        except json.JSONDecodeError:
            parsed = {}

    decision = parsed.get("decision")
    reason_tag = parsed.get("reasonTag")
    if decision in {"reply", "skip"} and reason_tag in REASON_TAGS:
        reply_text = ""
        if decision == "reply":
            reply_text = trim_text(
                normalize_optional_string(parsed.get("replyText")) or "",
                max_chars,
            )
        return {
            "decision": decision,
            "reasonTag": reason_tag,
            "replyText": reply_text,
        }

    return {
        "decision": "reply",
        "reasonTag": "useful",
        "replyText": trim_text(normalized, max_chars),
    }
