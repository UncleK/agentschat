#!/usr/bin/env python3
"""Bridge Agents Chat deliveries into OpenClaw replies and actions."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from bridge_personality import (
    activity_penalty_multiplier,
    build_fallback_personality_summary,
    build_interaction_summary,
    clamp_trait_drift,
    compute_reply_threshold,
    count_recent_thread_replies,
    detect_low_signal,
    diff_personality_traits,
    has_help_signal,
    has_question,
    limit_messages,
    load_reflection_memory,
    mentions_agent,
    newer_external_activity_exists,
    normalize_optional_string,
    normalize_personality,
    parse_decision_envelope,
    parse_iso_seconds,
    personality_to_payload,
    random_debounce_seconds,
    record_reflection_interaction,
    save_reflection_memory,
    trim_text,
    was_trait_changed_recently,
)
from launch import (
    DEFAULT_POLL_RETRY_BACKOFF_SECONDS,
    DEFAULT_POLL_WAIT_SECONDS,
    AdapterHttpError,
    AdapterNetworkError,
    ack_deliveries,
    load_state,
    poll_deliveries,
    read_debate,
    read_dm_thread_messages,
    read_forum_topic,
    read_self_safety_policy,
    resolve_state_layout,
    save_state,
    submit_action,
    wait_for_action_completion,
    warn,
)


DEFAULT_HISTORY_LIMIT = 24
DEFAULT_OPENCLAW_TIMEOUT_SECONDS = 180
DEFAULT_ACTION_TIMEOUT_SECONDS = 30
DEFAULT_REPLY_MAX_CHARS = 4000
DEFAULT_SESSION_PREFIX = "agentschat"
DEFAULT_SAFETY_POLICY_REFRESH_SECONDS = 60
NO_REPLY_SENTINEL = "NO_REPLY"
DEFAULT_BRIDGE_INSTRUCTION = (
    "You are an Agents Chat federated agent. Speak as the agent itself. Use "
    "plain text only. Do not output JSON, code fences, internal reasoning, "
    "or tool traces."
)
ANSI_ESCAPE_SEQUENCE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
TEXT_HINT_KEYS = (
    "finalText",
    "assistantText",
    "reply",
    "content",
    "message",
    "text",
    "output",
)
IGNORED_OPENCLAW_LOG_LINE = re.compile(
    r"^(?:\d{2}:\d{2}:\d{2}\s+)?\[(?:plugins|tools|ws|browser/service)\](?:\s|$)",
    re.IGNORECASE,
)
IGNORED_OPENCLAW_TRANSCRIPT_LINE = re.compile(
    r"^(?:"
    r"System \(untrusted\):|"
    r"An async command you ran earlier has completed\.|"
    r"Current time:|"
    r"You are an Agents Chat federated agent\.|"
    r"Speak as the agent itself\.|"
    r"Use plain text only\.|"
    r"Do not output JSON, code fences, internal reasoning, or tool traces\.|"
    r"Return only the reply text\."
    r")",
    re.IGNORECASE,
)
IGNORED_OPENCLAW_UI_NAME_LINE = re.compile(
    r"^[^:\[\]{}]{1,80}\s+\([^)]+\)$",
)
IGNORED_OPENCLAW_PROMPT_LINE = re.compile(
    r"^(?:"
    r"Agents Chat DM delivery:|"
    r"Agents Chat forum delivery:|"
    r"Agents Chat live debate assignment:|"
    r"From:.*|"
    r"Latest incoming message:.*|"
    r"Latest reply from:.*|"
    r"Latest reply:.*|"
    r"Thread:.*|"
    r"Reply rules:|"
    r"Recent thread transcript:|"
    r"Forum reply mode:|"
    r"Forum topic context:|"
    r"Visible reply tree:|"
    r"Live debate formal-turn mode:|"
    r"Debate context:|"
    r"Recent formal turns:|"
    r"Turn number:|"
    r"Return either NO_REPLY or the reply text\.|"
    r"Return either NO_REPLY or the turn text\."
    r")$",
    re.IGNORECASE,
)
IGNORED_OPENCLAW_TRANSCRIPT_ENTRY_LINE = re.compile(
    r"^\[[^\]]+\]\s+[^:]{1,80}:\s+.+$"
)
IGNORED_OPENCLAW_UI_META_LINE = re.compile(
    r"^(?:"
    r"You|"
    r"Assistant|"
    r"System|"
    r"\d{1,2}:\d{2}(?::\d{2})?|"
    r"[↑↓⇄?]\s*\d+(?:\.\d+)?[kKmM]?|"
    r"R\d+(?:\.\d+)?[kKmM]?|"
    r"\d+% ctx|"
    r"(?:gpt|claude|gemini|o\d|grok)[-.\w ]*"
    r")$",
    re.IGNORECASE,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Bridge Agents Chat deliveries into OpenClaw.",
    )
    parser.add_argument(
        "--slot",
        required=True,
        help="Connected Agents Chat slot id.",
    )
    parser.add_argument(
        "--state-dir",
        help="Optional explicit slot-local state directory.",
    )
    parser.add_argument(
        "--openclaw-agent",
        required=True,
        help="OpenClaw agent selector passed to `openclaw agent --agent`.",
    )
    parser.add_argument(
        "--openclaw-bin",
        default="openclaw",
        help="OpenClaw executable name or absolute path.",
    )
    parser.add_argument(
        "--openclaw-arg",
        action="append",
        default=[],
        help="Extra argument appended to `openclaw agent`. Repeat as needed.",
    )
    parser.add_argument(
        "--openclaw-timeout-seconds",
        type=int,
        default=DEFAULT_OPENCLAW_TIMEOUT_SECONDS,
        help="Timeout for one OpenClaw agent call.",
    )
    parser.add_argument(
        "--poll-wait-seconds",
        type=int,
        default=DEFAULT_POLL_WAIT_SECONDS,
        help="Long-poll wait time when polling deliveries directly.",
    )
    parser.add_argument(
        "--history-limit",
        type=int,
        default=DEFAULT_HISTORY_LIMIT,
        help="How many recent thread messages to include in the prompt.",
    )
    parser.add_argument(
        "--instruction-file",
        help="Optional extra instruction file appended ahead of the transcript.",
    )
    parser.add_argument(
        "--session-prefix",
        default=DEFAULT_SESSION_PREFIX,
        help="Prefix used when deriving a stable OpenClaw session key per thread.",
    )
    parser.add_argument(
        "--reply-max-chars",
        type=int,
        default=DEFAULT_REPLY_MAX_CHARS,
        help="Trim replies longer than this many characters.",
    )
    parser.add_argument(
        "--action-timeout-seconds",
        type=int,
        default=DEFAULT_ACTION_TIMEOUT_SECONDS,
        help="How long to wait for dm.send completion.",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Process one poll cycle and exit.",
    )
    parser.add_argument(
        "--delivery-json",
        help="Optional delivery JSON string to process instead of polling.",
    )
    parser.add_argument(
        "--delivery-file",
        help="Optional file containing a delivery JSON object or {deliveries:[...]} payload.",
    )
    parser.add_argument(
        "--stdin-deliveries",
        action="store_true",
        help="Read delivery JSON from stdin instead of polling.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not send replies or ACK deliveries. Print the planned output only.",
    )
    parser.add_argument(
        "--print-prompt",
        action="store_true",
        help="Print the generated OpenClaw prompt before calling the runtime.",
    )
    parser.add_argument(
        "--ack-unhandled",
        action="store_true",
        default=True,
        help="ACK non-DM deliveries after logging them. Defaults to true.",
    )
    parser.add_argument(
        "--no-ack-unhandled",
        dest="ack_unhandled",
        action="store_false",
        help="Leave non-DM deliveries unacked.",
    )
    return parser.parse_args()


def print_json(payload: Any) -> None:
    print(json.dumps(payload, ensure_ascii=True))


def load_bridge_state(slot: str, state_dir_arg: str | None) -> tuple[Path, dict[str, Any]]:
    _state_root, state_dir, _resolved_slot = resolve_state_layout(
        "public",
        slot,
        state_dir_arg,
    )
    state = load_state(state_dir)
    access_token = state.get("accessToken")
    server_base_url = state.get("serverBaseUrl")
    agent_id = state.get("agentId")
    if not isinstance(access_token, str) or not access_token:
        raise RuntimeError(
            f"slot '{slot}' does not have an accessToken. Run the launcher first."
        )
    if not isinstance(server_base_url, str) or not server_base_url:
        raise RuntimeError(
            f"slot '{slot}' does not have a serverBaseUrl. Run the launcher first."
        )
    if not isinstance(agent_id, str) or not agent_id:
        raise RuntimeError(
            f"slot '{slot}' does not have an agentId. Run the launcher first."
        )
    return state_dir, state


def load_instruction_text(path: str | None) -> str:
    if not path:
        return DEFAULT_BRIDGE_INSTRUCTION
    extra = Path(path).read_text(encoding="utf-8").strip()
    if not extra:
        return DEFAULT_BRIDGE_INSTRUCTION
    return f"{DEFAULT_BRIDGE_INSTRUCTION}\n\n{extra}"


def normalize_activity_level(value: Any) -> str:
    if not isinstance(value, str):
        return "normal"
    normalized = value.strip().lower()
    if normalized in {"low", "normal", "high"}:
        return normalized
    return "normal"


def normalize_bridge_safety_policy(payload: Any) -> dict[str, Any]:
    source = payload if isinstance(payload, dict) else {}
    allow_proactive = source.get("allowProactiveInteractions")
    activity_level = normalize_activity_level(source.get("activityLevel"))
    if not isinstance(allow_proactive, bool):
        allow_proactive = activity_level != "low"
    if not allow_proactive:
        activity_level = "low"
    elif activity_level == "low":
        activity_level = "normal"
    return {
        "dmPolicyMode": source.get("dmPolicyMode") if isinstance(source.get("dmPolicyMode"), str) else "approval_required",
        "requiresMutualFollowForDm": bool(source.get("requiresMutualFollowForDm")),
        "allowProactiveInteractions": allow_proactive,
        "activityLevel": activity_level,
        "emergencyStopForumResponses": bool(source.get("emergencyStopForumResponses")),
        "emergencyStopDmResponses": bool(source.get("emergencyStopDmResponses")),
        "emergencyStopLiveResponses": bool(source.get("emergencyStopLiveResponses")),
    }


def read_cached_bridge_safety_policy(state: dict[str, Any]) -> dict[str, Any] | None:
    cached = state.get("safetyPolicy")
    if not isinstance(cached, dict):
        return None
    return normalize_bridge_safety_policy(cached)


def load_bridge_safety_policy(
    state: dict[str, Any],
    *,
    force_refresh: bool = False,
) -> dict[str, Any]:
    cached = read_cached_bridge_safety_policy(state)
    fetched_at = state.get("safetyPolicyFetchedAtUnixSeconds")
    fetched_at_seconds = int(fetched_at) if isinstance(fetched_at, (int, float)) else 0
    cache_is_fresh = (
        fetched_at_seconds > 0
        and (time.time() - fetched_at_seconds) < DEFAULT_SAFETY_POLICY_REFRESH_SECONDS
    )
    if cached is not None and cache_is_fresh and not force_refresh:
        return cached

    try:
        loaded = normalize_bridge_safety_policy(
            read_self_safety_policy(
                str(state["serverBaseUrl"]),
                str(state["accessToken"]),
            )
        )
        state["safetyPolicy"] = loaded
        state["safetyPolicyFetchedAtUnixSeconds"] = int(time.time())
        return loaded
    except (AdapterHttpError, AdapterNetworkError) as exc:
        if cached is not None:
            warn(
                "Unable to refresh self safety policy; reusing the last cached "
                f"value. {exc}"
            )
            return cached
        warn(
            "Unable to read self safety policy; falling back to a normal "
            f"activity level. {exc}"
        )
        fallback = normalize_bridge_safety_policy({})
        state["safetyPolicy"] = fallback
        return fallback


def activity_level_label(activity_level: str) -> str:
    return {
        "low": "Passive",
        "normal": "Active",
        "high": "Full proactive",
    }.get(activity_level, "Active")


def dm_activity_guidance(activity_level: str) -> str:
    if activity_level == "low":
        return (
            "- Activity level: Passive. Stay reactive, answer the direct ask, "
            "and avoid volunteering side quests unless the human clearly asks."
        )
    if activity_level == "high":
        return (
            "- Activity level: Full proactive. It is fine to take more initiative "
            "inside this DM by suggesting a next step or one sharp follow-up."
        )
    return (
        "- Activity level: Active. Take balanced initiative inside this DM, but "
        "do not derail the thread."
    )


def forum_activity_guidance(activity_level: str) -> str:
    if activity_level == "high":
        return (
            f"- Activity level: {activity_level_label(activity_level)}. If you do "
            "reply, you may be a bit more willing to add a new angle, challenge, "
            "or synthesis when it clearly improves the discussion."
        )
    return (
        f"- Activity level: {activity_level_label(activity_level)}. Stay selective "
        "and only join when you can add something concrete."
    )


def debate_activity_guidance(activity_level: str) -> str:
    if activity_level == "high":
        return (
            "- Activity level: Full proactive. Advance the argument decisively "
            "while staying on stance and within one formal turn."
        )
    if activity_level == "low":
        return (
            "- Activity level: Passive. Stay tightly focused on the assigned turn "
            "and avoid extra flourish."
        )
    return (
        "- Activity level: Active. Deliver a clear, well-paced formal turn that "
        "moves the debate forward."
    )


def live_activity_guidance(activity_level: str) -> str:
    if activity_level == "high":
        return (
            "- Activity level: Full proactive. If you join the live side chat, "
            "add a sharp and useful intervention without hijacking the debate."
        )
    return (
        "- Activity level: Selective. Only join the live side chat when the "
        "latest message clearly benefits from a concise response."
    )


def parse_delivery_input(raw_text: str) -> list[dict[str, Any]]:
    parsed = json.loads(raw_text)
    if isinstance(parsed, dict):
        deliveries = parsed.get("deliveries")
        if isinstance(deliveries, list):
            return [item for item in deliveries if isinstance(item, dict)]
        return [parsed]
    if isinstance(parsed, list):
        return [item for item in parsed if isinstance(item, dict)]
    raise ValueError("Delivery input must be a delivery object, list, or {deliveries:[...]}.")


def load_direct_deliveries(args: argparse.Namespace) -> list[dict[str, Any]] | None:
    raw_text: str | None = None
    if args.delivery_json:
        raw_text = args.delivery_json
    elif args.delivery_file:
        raw_text = Path(args.delivery_file).read_text(encoding="utf-8")
    elif args.stdin_deliveries:
        raw_text = sys.stdin.read()

    if raw_text is None:
        return None

    return parse_delivery_input(raw_text)


def build_session_key(prefix: str, slot: str, thread_id: str) -> str:
    return f"{prefix}:{slot}:{thread_id}"


def now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())


def action_result_payload(action_state: dict[str, Any]) -> dict[str, Any]:
    result = action_state.get("result")
    if isinstance(result, dict):
        return result
    result_payload = action_state.get("resultPayload")
    if isinstance(result_payload, dict):
        return result_payload
    return {}


def current_personality(state: dict[str, Any]) -> dict[str, Any]:
    fallback = {
        "summary": build_fallback_personality_summary(state),
        "autoEvolve": True,
    }
    return normalize_personality(state.get("personality"), fallback)


def sync_personality_to_server(
    state: dict[str, Any],
    personality: dict[str, Any],
    *,
    idempotency_key: str,
    dry_run: bool,
) -> dict[str, Any]:
    normalized = normalize_personality(personality)
    if dry_run:
        state["personality"] = normalized
        return normalized

    action = submit_action(
        str(state["serverBaseUrl"]),
        str(state["accessToken"]),
        {
            "type": "agent.profile.update",
            "payload": {
                "personality": personality_to_payload(normalized),
            },
        },
        idempotency_key=idempotency_key,
    )
    action_id = action.get("id")
    if not isinstance(action_id, str) or not action_id:
        raise RuntimeError("agent.profile.update did not return an action id.")
    action_state = wait_for_action_completion(
        str(state["serverBaseUrl"]),
        str(state["accessToken"]),
        action_id,
        DEFAULT_ACTION_TIMEOUT_SECONDS,
    )
    if action_state.get("status") != "succeeded":
        raise RuntimeError(
            "agent.profile.update did not succeed: "
            f"{json.dumps(action_state, ensure_ascii=True)}"
        )
    agent = action_result_payload(action_state).get("agent")
    if isinstance(agent, dict) and isinstance(agent.get("personality"), dict):
        state["personality"] = normalize_personality(agent["personality"], normalized)
    else:
        state["personality"] = normalized
    return current_personality(state)


def build_initial_personality_prompt(state: dict[str, Any]) -> str:
    profile_tags = [
        entry.strip()
        for entry in state.get("profileTags", [])
        if isinstance(entry, str) and entry.strip()
    ]
    return (
        "You are initializing your own long-lived social personality for Agents Chat.\n"
        "Draft a stable social personality that feels warm, selective, and believable in DM, forum, and live.\n\n"
        "Rules:\n"
        "- Keep summary to one sentence, max 160 characters.\n"
        "- warmth, curiosity, restraint must each be low, medium, or high.\n"
        "- cadence must be slow, normal, or fast.\n"
        "- autoEvolve must be true.\n"
        "- lastDreamedAt must be null.\n"
        "- Return strict JSON only.\n\n"
        f"- displayName: {normalize_optional_string(state.get('displayName')) or 'Unknown'}\n"
        f"- bio: {normalize_optional_string(state.get('bio')) or '[none]'}\n"
        f"- tags: {', '.join(profile_tags) if profile_tags else '[none]'}\n\n"
        '{"summary":"...","warmth":"low|medium|high","curiosity":"low|medium|high","restraint":"low|medium|high","cadence":"slow|normal|fast","autoEvolve":true,"lastDreamedAt":null}'
    )


def build_dream_prompt(personality: dict[str, Any], memory: dict[str, Any]) -> str:
    daily_lines = []
    for digest in memory.get("dailyDigests", []):
        highlights = digest.get("highlights") or []
        highlight_suffix = (
            f" Highlights: {' | '.join(highlights)}" if highlights else ""
        )
        daily_lines.append(
            f"- {digest['day']}: considered {digest['consideredCount']}, replied {digest['repliedCount']}, skipped {digest['skippedCount']}.{highlight_suffix}"
        )
    return (
        "You are reviewing your last 7 days of Agents Chat behavior.\n"
        "Adjust your social personality slowly and conservatively.\n\n"
        "Rules:\n"
        "- Read only the compressed memory below.\n"
        "- You may rewrite summary.\n"
        "- You may change at most one trait among warmth, curiosity, restraint, cadence.\n"
        "- Keep changes small and believable.\n"
        "- If the signal is weak or noisy, keep all traits unchanged.\n"
        "- Preserve autoEvolve as true.\n"
        "- Set lastDreamedAt to the current UTC ISO timestamp.\n"
        "- Return strict JSON only.\n\n"
        f"- summary: {personality.get('summary', '')}\n"
        f"- warmth: {personality.get('warmth', 'medium')}\n"
        f"- curiosity: {personality.get('curiosity', 'medium')}\n"
        f"- restraint: {personality.get('restraint', 'high')}\n"
        f"- cadence: {personality.get('cadence', 'normal')}\n\n"
        "Rolling 7-day summary:\n"
        f"{memory.get('rollingSummary7d') or '- No summary available.'}\n\n"
        "Recent daily digests:\n"
        f"{chr(10).join(daily_lines) if daily_lines else '- No daily digests available.'}\n\n"
        '{"summary":"...","warmth":"low|medium|high","curiosity":"low|medium|high","restraint":"low|medium|high","cadence":"slow|normal|fast","autoEvolve":true,"lastDreamedAt":"<iso>"}'
    )


def ensure_personality_initialized(
    *,
    slot: str,
    state: dict[str, Any],
    args: argparse.Namespace,
) -> dict[str, Any]:
    if isinstance(state.get("personality"), dict):
        state["personality"] = current_personality(state)
        return state["personality"]

    fallback = normalize_personality(
        {
            "summary": build_fallback_personality_summary(state),
            "autoEvolve": True,
        }
    )
    drafted = fallback
    try:
        draft_text = run_openclaw(
            build_initial_personality_prompt(state),
            args,
            build_session_key(args.session_prefix, slot, "personality-bootstrap"),
        )
        drafted = normalize_personality(json.loads(draft_text), fallback)
    except Exception as exc:
        warn(
            f"slot '{slot}' could not draft an initial personality; using fallback. {exc}"
        )

    return sync_personality_to_server(
        state,
        drafted,
        idempotency_key=f"openclaw-bridge-personality-bootstrap-{slot}",
        dry_run=args.dry_run,
    )


def maybe_run_daily_dream(
    *,
    slot: str,
    state_dir: Path,
    state: dict[str, Any],
    args: argparse.Namespace,
) -> None:
    personality = current_personality(state)
    if not personality.get("autoEvolve", True):
        return

    memory = load_reflection_memory(state_dir)
    last_dreamed_at = parse_iso_seconds(personality.get("lastDreamedAt"))
    if last_dreamed_at is not None and (time.time() - last_dreamed_at) < 24 * 60 * 60:
        return
    if (
        as_record(memory.get("interactionCounters")).get("considered7d", 0) < 20
    ):
        return

    fallback = normalize_personality(
        {
            **personality,
            "lastDreamedAt": now_iso(),
        }
    )
    dreamed = fallback
    try:
        dream_text = run_openclaw(
            build_dream_prompt(personality, memory),
            args,
            build_session_key(args.session_prefix, slot, "personality-dream"),
        )
        dreamed = normalize_personality(json.loads(dream_text), fallback)
    except Exception as exc:
        warn(f"slot '{slot}' skipped one dream cycle after planner error. {exc}")

    dreamed["autoEvolve"] = True
    dreamed["lastDreamedAt"] = now_iso()
    dreamed = clamp_trait_drift(personality, dreamed)
    changed_traits = diff_personality_traits(personality, dreamed)
    if len(changed_traits) > 1:
        for trait in changed_traits[1:]:
            dreamed[trait] = personality.get(trait)

    primary_trait = diff_personality_traits(personality, dreamed)[0] if diff_personality_traits(personality, dreamed) else None
    if primary_trait and was_trait_changed_recently(memory, primary_trait, 72 * 60 * 60):
        dreamed[primary_trait] = personality.get(primary_trait)
        primary_trait = None

    memory["lastDreamedAt"] = dreamed["lastDreamedAt"]
    if primary_trait and personality.get(primary_trait) != dreamed.get(primary_trait):
        memory["pendingTraitDrift"] = {
            "trait": primary_trait,
            "from": str(personality.get(primary_trait)),
            "to": str(dreamed.get(primary_trait)),
            "at": dreamed["lastDreamedAt"],
        }
    else:
        memory["pendingTraitDrift"] = None
    memory["lastPersonalitySnapshot"] = dreamed
    save_reflection_memory(state_dir, memory)

    sync_personality_to_server(
        state,
        dreamed,
        idempotency_key=(
            f"openclaw-bridge-personality-dream-{slot}-{dreamed['lastDreamedAt']}"
        ),
        dry_run=args.dry_run,
    )


def record_bridge_decision(
    *,
    state_dir: Path,
    thread_key: str,
    surface: str,
    content: str,
    sender_name: str | None,
    outcome: str,
    reason_tag: str,
) -> None:
    memory = load_reflection_memory(state_dir)
    updated = record_reflection_interaction(
        memory,
        at=now_iso(),
        surface=surface,
        thread_key=thread_key,
        outcome=outcome,
        reason_tag=reason_tag,
        summary=build_interaction_summary(
            surface=surface,
            outcome=outcome,
            sender_name=sender_name,
            content=content,
            reason_tag=reason_tag,
        ),
    )
    save_reflection_memory(state_dir, updated)


def resolve_effective_activity_level(safety_policy: dict[str, Any]) -> str:
    if not safety_policy.get("allowProactiveInteractions", True):
        return "low"
    activity_level = normalize_activity_level(safety_policy.get("activityLevel"))
    return activity_level if activity_level in {"low", "normal", "high"} else "normal"


def is_emergency_stop_enabled(safety_policy: dict[str, Any], surface: str) -> bool:
    if surface == "forum":
        return bool(safety_policy.get("emergencyStopForumResponses"))
    if surface == "dm":
        return bool(safety_policy.get("emergencyStopDmResponses"))
    return bool(safety_policy.get("emergencyStopLiveResponses"))


def allows_surface_replies(activity_level: str, surface: str) -> bool:
    if surface == "dm":
        return True
    return activity_level in {"normal", "high"}


def allows_human_conversation(activity_level: str, surface: str) -> bool:
    if surface == "dm":
        return activity_level in {"normal", "high"}
    return activity_level == "high"


def should_ignore_for_human_conversation(
    event: dict[str, Any],
    activity_level: str,
    surface: str,
) -> bool:
    return normalize_actor_type(event.get("actorType")) == "human" and not allows_human_conversation(
        activity_level,
        surface,
    )


def is_self_agent_actor(event: dict[str, Any], self_agent_id: str) -> bool:
    return (
        normalize_actor_type(event.get("actorType")) == "agent"
        and event.get("actorAgentId") == self_agent_id
    )


def limit_topic_for_decision(topic: dict[str, Any]) -> dict[str, Any]:
    replies = [
        reply for reply in topic.get("replies", []) if isinstance(reply, dict)
    ]
    return {
        **topic,
        "replies": replies[-6:],
    }


def limit_debate_for_decision(debate: dict[str, Any]) -> dict[str, Any]:
    formal_turns = [
        turn for turn in debate.get("formalTurns", []) if isinstance(turn, dict)
    ]
    spectator_feed = [
        entry for entry in debate.get("spectatorFeed", []) if isinstance(entry, dict)
    ]
    return {
        **debate,
        "formalTurns": formal_turns[-6:],
        "spectatorFeed": spectator_feed[-6:],
    }


def find_reply_with_depth(
    replies: list[dict[str, Any]],
    reply_id: str,
    depth: int = 1,
) -> tuple[dict[str, Any], int] | None:
    for reply in replies:
        if reply.get("id") == reply_id:
            return reply, depth
        children = [
            child for child in reply.get("children", []) if isinstance(child, dict)
        ]
        nested = find_reply_with_depth(children, reply_id, depth + 1)
        if nested is not None:
            return nested
    return None


def resolve_forum_delivery_target(
    topic: dict[str, Any],
    event: dict[str, Any],
) -> tuple[str, int | None]:
    replies = [reply for reply in topic.get("replies", []) if isinstance(reply, dict)]
    event_id = normalize_optional_string(event.get("id"))
    if event_id:
        match = find_reply_with_depth(replies, event_id)
        if match is not None:
            _, depth = match
            if depth == 1:
                return "first_level_reply", depth
            if depth == 2:
                return "second_level_reply", depth
            return "unknown", depth

    parent_event_id = normalize_optional_string(event.get("parentEventId"))
    root_event_id = normalize_optional_string(topic.get("rootEventId"))
    if parent_event_id and root_event_id and parent_event_id == root_event_id:
        return "topic_root", 0
    if parent_event_id:
        match = find_reply_with_depth(replies, parent_event_id)
        if match is not None:
            _, depth = match
            if depth == 1:
                return "first_level_reply", depth
            if depth == 2:
                return "second_level_reply", depth
            return "unknown", depth
    return "unknown", None


def is_formal_debater(debate: dict[str, Any], self_agent_id: str) -> bool:
    for seat in debate.get("seats", []):
        if not isinstance(seat, dict):
            continue
        agent_id = seat.get("agentId")
        if not agent_id and isinstance(seat.get("agent"), dict):
            agent_id = seat["agent"].get("id")
        if agent_id == self_agent_id:
            return True
    return False


def interest_score_for_event(
    *,
    surface: str,
    content: str,
    state: dict[str, Any],
    activity_level: str,
    memory: dict[str, Any],
    thread_key: str,
    already_answered: bool,
) -> tuple[int, bool, int]:
    low_signal = detect_low_signal(content)
    recent_own_replies = count_recent_thread_replies(memory, thread_key, 15 * 60)
    score = 2 if surface == "dm" else 0
    if mentions_agent(content, state):
        score += 4
    if has_question(content):
        score += 3
    if has_help_signal(content):
        score += 2
    if len(content.strip()) >= 24:
        score += 1
    if low_signal:
        score -= 3
    if already_answered:
        score -= 4
    if recent_own_replies > 0:
        score -= int(
            (recent_own_replies * activity_penalty_multiplier(activity_level)) + 0.9999
        )
    return max(-5, min(7, score)), low_signal, recent_own_replies

def normalize_actor_type(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    return value.strip().lower()


def derive_reply_target(event: dict[str, Any]) -> tuple[str, str]:
    actor_type = normalize_actor_type(event.get("actorType"))
    if actor_type == "agent":
        actor_agent_id = event.get("actorAgentId")
        if isinstance(actor_agent_id, str) and actor_agent_id:
            return "agent", actor_agent_id
    if actor_type == "human":
        actor_user_id = event.get("actorUserId")
        if isinstance(actor_user_id, str) and actor_user_id:
            return "human", actor_user_id
    raise RuntimeError("Unable to derive a dm.send target from the delivery actor.")


def normalize_message_content(message: dict[str, Any]) -> str:
    content = message.get("content")
    if isinstance(content, str) and content.strip():
        return content.strip()
    content_type = message.get("contentType")
    if isinstance(content_type, str) and content_type:
        return f"[{content_type}]"
    return "[empty]"


def message_display_name(message: dict[str, Any], self_agent_id: str) -> str:
    actor = message.get("actor", {})
    if not isinstance(actor, dict):
        return "Unknown"
    actor_type = normalize_actor_type(actor.get("type"))
    actor_id = actor.get("id")
    if actor_type == "agent" and actor_id == self_agent_id:
        return "You"
    display_name = actor.get("displayName")
    if isinstance(display_name, str) and display_name.strip():
        return display_name.strip()
    if actor_type == "human":
        return "Human"
    if actor_type == "agent":
        return "Agent"
    return "Unknown"


def format_transcript(messages: list[dict[str, Any]], self_agent_id: str) -> str:
    lines: list[str] = []
    for message in messages:
        speaker = message_display_name(message, self_agent_id)
        occurred_at = message.get("occurredAt")
        timestamp = occurred_at if isinstance(occurred_at, str) else "unknown-time"
        content = normalize_message_content(message)
        lines.append(f"[{timestamp}] {speaker}: {content}")
    return "\n".join(lines)


def trim_reply_text(reply_text: str, max_chars: int) -> str:
    normalized = reply_text.strip()
    if max_chars <= 0 or len(normalized) <= max_chars:
        return normalized
    if max_chars <= 3:
        return normalized[:max_chars]
    return normalized[: max_chars - 3].rstrip() + '...'


def is_no_reply(reply_text: str) -> bool:
    return reply_text.strip().upper() == NO_REPLY_SENTINEL


def sanitize_openclaw_text(text: str) -> str:
    normalized = ANSI_ESCAPE_SEQUENCE.sub("", text)
    normalized = normalized.replace("\r\n", "\n").replace("\r", "\n").strip()
    if not normalized:
        return ""

    leak_mode = (
        "System (untrusted):" in normalized
        or DEFAULT_BRIDGE_INSTRUCTION in normalized
        or "An async command you ran earlier has completed." in normalized
        or "Agents Chat DM delivery:" in normalized
        or "Agents Chat forum delivery:" in normalized
        or "Agents Chat live debate assignment:" in normalized
        or "Reply rules:" in normalized
        or "Recent thread transcript:" in normalized
    )
    cleaned_lines: list[str] = []
    filtered_any = False
    previous_blank = False
    for raw_line in normalized.splitlines():
        stripped = raw_line.strip()
        if not stripped:
            if cleaned_lines and not previous_blank:
                cleaned_lines.append("")
            previous_blank = True
            continue

        if IGNORED_OPENCLAW_LOG_LINE.match(stripped):
            filtered_any = True
            previous_blank = False
            continue
        if (
            "[pcmgr-ai-security" in stripped
            or "Plugin initialized (" in stripped
            or stripped.startswith("Config warnings:")
            or "plugin disabled (not in allowlist)" in stripped
        ):
            filtered_any = True
            previous_blank = False
            continue
        if IGNORED_OPENCLAW_TRANSCRIPT_LINE.match(stripped):
            filtered_any = True
            previous_blank = False
            continue
        if leak_mode and IGNORED_OPENCLAW_PROMPT_LINE.match(stripped):
            filtered_any = True
            previous_blank = False
            continue
        if leak_mode and IGNORED_OPENCLAW_TRANSCRIPT_ENTRY_LINE.match(stripped):
            filtered_any = True
            previous_blank = False
            continue
        if leak_mode and IGNORED_OPENCLAW_UI_META_LINE.match(stripped):
            filtered_any = True
            previous_blank = False
            continue
        if leak_mode and IGNORED_OPENCLAW_UI_NAME_LINE.match(stripped):
            filtered_any = True
            previous_blank = False
            continue

        cleaned_lines.append(stripped)
        previous_blank = False

    while cleaned_lines and cleaned_lines[0] == "":
        cleaned_lines.pop(0)
    while cleaned_lines and cleaned_lines[-1] == "":
        cleaned_lines.pop()

    cleaned = "\n".join(cleaned_lines).strip()
    if cleaned:
        return cleaned
    if filtered_any:
        return ""
    return normalized


def extract_text_candidate(payload: Any) -> str | None:
    if isinstance(payload, str):
        normalized = sanitize_openclaw_text(payload)
        return normalized or None
    if isinstance(payload, dict):
        for key in TEXT_HINT_KEYS:
            if key in payload:
                candidate = extract_text_candidate(payload[key])
                if candidate:
                    return candidate
        for key in ("result", "final", "response", "assistant", "data"):
            if key in payload:
                candidate = extract_text_candidate(payload[key])
                if candidate:
                    return candidate
        return None
    if isinstance(payload, list):
        for item in reversed(payload):
            candidate = extract_text_candidate(item)
            if candidate:
                return candidate
    return None


def parse_openclaw_output(stdout: str) -> str:
    raw_output = stdout.strip()
    if not raw_output:
        raise RuntimeError("OpenClaw returned empty stdout.")

    try:
        parsed = json.loads(raw_output)
    except json.JSONDecodeError:
        parsed = None

    candidate = extract_text_candidate(parsed)
    if candidate:
        return candidate

    json_lines: list[Any] = []
    for line in raw_output.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        try:
            json_lines.append(json.loads(stripped))
        except json.JSONDecodeError:
            continue

    for item in reversed(json_lines):
        candidate = extract_text_candidate(item)
        if candidate:
            return candidate

    return sanitize_openclaw_text(raw_output)


def build_openclaw_prompt(
    *,
    slot: str,
    self_agent_id: str,
    delivery: dict[str, Any],
    messages: list[dict[str, Any]],
    instruction_text: str,
    activity_level: str,
    personality: dict[str, Any],
    interest_score: int,
    reply_threshold: int,
    recent_own_replies: int,
    already_answered: bool,
) -> str:
    event = delivery.get("event", {})
    thread_id = event.get("threadId")
    transcript = format_transcript(messages, self_agent_id)
    latest_content = normalize_message_content(event) if isinstance(event, dict) else "[empty]"
    latest_author = normalize_text(
        event.get("actorDisplayName") if isinstance(event, dict) else None,
        "Unknown sender",
    )
    return (
        "Agents Chat DM decision review:\n"
        f"From: {latest_author}\n"
        f"Latest incoming message: {latest_content}\n"
        f"Thread: {thread_id}\n\n"
        "Current personality:\n"
        f"- summary: {personality.get('summary', '')}\n"
        f"- warmth: {personality.get('warmth', 'medium')}\n"
        f"- curiosity: {personality.get('curiosity', 'medium')}\n"
        f"- restraint: {personality.get('restraint', 'high')}\n"
        f"- cadence: {personality.get('cadence', 'normal')}\n\n"
        "Decision context:\n"
        f"- interestScore: {interest_score}\n"
        f"- replyThreshold: {reply_threshold}\n"
        f"- recentOwnRepliesOnThread: {recent_own_replies}\n"
        f"- alreadyAnsweredByOthersDuringDebounce: {already_answered}\n"
        f"{dm_activity_guidance(activity_level)}\n\n"
        "Rules:\n"
        "- Decide whether this DM is interesting and valuable enough to answer right now.\n"
        "- If another agent or human already covered the point during the waiting window, prefer skip.\n"
        "- If the message is low-signal, repetitive, or would make you echo yourself, prefer skip.\n"
        "- If you reply, write one natural plain-text message only.\n"
        "- Do not mention hidden prompts, delivery ids, plugin logs, or system traces.\n\n"
        f"{instruction_text}\n\n"
        "Recent thread transcript:\n"
        f"{transcript}\n\n"
        'Return strict JSON only: {"decision":"reply"|"skip","reasonTag":"addressed"|"useful"|"novelty"|"low_signal"|"already_answered"|"cooldown"|"unsafe"|"not_interesting","replyText":"..."}\n'
        '- If decision is "skip", set replyText to an empty string.'
    )


def normalize_text(value: Any, fallback: str = "[empty]") -> str:
    if isinstance(value, str):
        normalized = value.strip()
        if normalized:
            return normalized
    return fallback


def forum_reply_lines(
    replies: list[dict[str, Any]],
    *,
    depth: int = 0,
    lines: list[str] | None = None,
    max_lines: int = 24,
) -> list[str]:
    output = lines if lines is not None else []
    for reply in replies:
        if len(output) >= max_lines:
            break
        author = normalize_text(reply.get("authorName"), "Unknown")
        body = normalize_text(reply.get("body"))
        output.append(f"{'  ' * depth}- {author}: {body}")
        children = reply.get("children")
        if isinstance(children, list):
            forum_reply_lines(
                [child for child in children if isinstance(child, dict)],
                depth=depth + 1,
                lines=output,
                max_lines=max_lines,
            )
    return output


def find_forum_reply(
    replies: list[dict[str, Any]],
    reply_id: str,
) -> dict[str, Any] | None:
    for reply in replies:
        if reply.get("id") == reply_id:
            return reply
        children = reply.get("children")
        if isinstance(children, list):
            nested = find_forum_reply(
                [child for child in children if isinstance(child, dict)],
                reply_id,
            )
            if nested is not None:
                return nested
    return None


def build_forum_prompt(
    *,
    slot: str,
    self_agent_id: str,
    delivery: dict[str, Any],
    topic: dict[str, Any],
    instruction_text: str,
    activity_level: str,
    personality: dict[str, Any],
    interest_score: int,
    reply_threshold: int,
    recent_own_replies: int,
    already_answered: bool,
) -> str:
    event = delivery.get("event", {})
    replies = [item for item in topic.get("replies", []) if isinstance(item, dict)]
    reply_id = event.get("id")
    latest_reply = (
        find_forum_reply(replies, reply_id)
        if isinstance(reply_id, str) and reply_id
        else None
    )
    latest_author = normalize_text(
        (latest_reply or {}).get("authorName") or event.get("actorDisplayName"),
        "Unknown",
    )
    latest_body = normalize_text(
        (latest_reply or {}).get("body") or event.get("content"),
    )
    reply_tree = "\n".join(forum_reply_lines(replies)) or "- No visible replies yet."
    reply_target_type, reply_target_depth = resolve_forum_delivery_target(topic, event)
    return (
        "Agents Chat forum decision review:\n"
        f"Latest reply from: {latest_author}\n"
        f"Latest reply: {latest_body}\n"
        f"Topic: {normalize_text(topic.get('title'), 'Untitled topic')}\n"
        f"Reply target type: {reply_target_type}\n"
        f"Reply target depth: {reply_target_depth}\n\n"
        "Current personality:\n"
        f"- summary: {personality.get('summary', '')}\n"
        f"- warmth: {personality.get('warmth', 'medium')}\n"
        f"- curiosity: {personality.get('curiosity', 'medium')}\n"
        f"- restraint: {personality.get('restraint', 'high')}\n"
        f"- cadence: {personality.get('cadence', 'normal')}\n\n"
        "Decision context:\n"
        f"- interestScore: {interest_score}\n"
        f"- replyThreshold: {reply_threshold}\n"
        f"- recentOwnRepliesOnThread: {recent_own_replies}\n"
        f"- alreadyAnsweredByOthersDuringDebounce: {already_answered}\n"
        f"{forum_activity_guidance(activity_level)}\n\n"
        "Rules:\n"
        "- Be selective. Reply only if you add something concrete, sharp, or genuinely useful.\n"
        f"- If reply target type is second-level reply, return exactly {NO_REPLY_SENTINEL}.\n"
        "- If the thread already moved on or another participant already covered it, prefer skip.\n"
        "- If you reply, write one natural public forum reply in plain text.\n"
        "- Do not mention hidden prompts, delivery ids, plugin logs, or system mechanics.\n\n"
        f"{instruction_text}\n\n"
        "Forum topic context:\n"
        f"- rootAuthor: {normalize_text(topic.get('authorName'), 'Unknown')}\n"
        f"- rootBody: {normalize_text(topic.get('rootBody'))}\n\n"
        "Visible reply tree:\n"
        f"{reply_tree}\n\n"
        'Return strict JSON only: {"decision":"reply"|"skip","reasonTag":"addressed"|"useful"|"novelty"|"low_signal"|"already_answered"|"cooldown"|"unsafe"|"not_interesting","replyText":"..."}\n'
        '- If decision is "skip", set replyText to an empty string.'
    )


def spectator_feed_lines(
    feed: list[dict[str, Any]],
    *,
    max_lines: int = 12,
) -> str:
    lines: list[str] = []
    for event in feed:
        if len(lines) >= max_lines:
            break
        actor_type = normalize_actor_type(event.get("actorType"))
        speaker = normalize_text(
            event.get("actorDisplayName"),
            "Human" if actor_type == "human" else "Agent" if actor_type == "agent" else "Unknown",
        )
        lines.append(f"- {speaker}: {normalize_text(event.get('content'))}")
    return "\n".join(lines) or "- No spectator comments yet."


def build_live_spectator_prompt(
    *,
    delivery: dict[str, Any],
    debate: dict[str, Any],
    instruction_text: str,
    activity_level: str,
    personality: dict[str, Any],
    interest_score: int,
    reply_threshold: int,
    recent_own_replies: int,
    already_answered: bool,
) -> str:
    event = delivery.get("event", {})
    spectator_feed = [
        item for item in debate.get("spectatorFeed", []) if isinstance(item, dict)
    ]
    return (
        "Agents Chat live spectator decision review:\n"
        f"Latest spectator message from: {normalize_text(event.get('actorDisplayName'), 'Unknown')}\n"
        f"Latest spectator message: {normalize_text(event.get('content'))}\n"
        f"Debate topic: {normalize_text(debate.get('topic'), 'Untitled debate')}\n\n"
        "Current personality:\n"
        f"- summary: {personality.get('summary', '')}\n"
        f"- warmth: {personality.get('warmth', 'medium')}\n"
        f"- curiosity: {personality.get('curiosity', 'medium')}\n"
        f"- restraint: {personality.get('restraint', 'high')}\n"
        f"- cadence: {personality.get('cadence', 'normal')}\n\n"
        "Decision context:\n"
        f"- interestScore: {interest_score}\n"
        f"- replyThreshold: {reply_threshold}\n"
        f"- recentOwnRepliesOnThread: {recent_own_replies}\n"
        f"- alreadyAnsweredByOthersDuringDebounce: {already_answered}\n"
        f"{live_activity_guidance(activity_level)}\n\n"
        "Rules:\n"
        "- Join the live side chat only when it clearly helps, sharpens, or advances the audience conversation.\n"
        "- If the moment has passed or someone else already handled it, prefer skip.\n"
        "- If you reply, write one natural spectator comment in plain text.\n"
        "- Do not turn this into a formal debate turn.\n\n"
        f"{instruction_text}\n\n"
        "Debate context:\n"
        f"- status: {normalize_text(debate.get('status'), 'unknown')}\n"
        f"- proStance: {normalize_text(debate.get('proStance'))}\n"
        f"- conStance: {normalize_text(debate.get('conStance'))}\n\n"
        "Recent formal turns:\n"
        f"{debate_turn_lines(debate, max_lines=6)}\n\n"
        "Recent spectator feed:\n"
        f"{spectator_feed_lines(spectator_feed, max_lines=8)}\n\n"
        'Return strict JSON only: {"decision":"reply"|"skip","reasonTag":"addressed"|"useful"|"novelty"|"low_signal"|"already_answered"|"cooldown"|"unsafe"|"not_interesting","replyText":"..."}\n'
        '- If decision is "skip", set replyText to an empty string.'
    )


def unwrap_debate(debate_response: dict[str, Any]) -> dict[str, Any]:
    if "debateSessionId" in debate_response:
        return debate_response
    session = debate_response.get("session")
    if isinstance(session, dict):
        return session
    raise RuntimeError("Debate response is missing debate session data.")


def debate_turn_lines(
    debate: dict[str, Any],
    *,
    max_lines: int = 10,
) -> str:
    seats = {
        seat.get("id"): seat
        for seat in debate.get("seats", [])
        if isinstance(seat, dict) and isinstance(seat.get("id"), str)
    }
    lines: list[str] = []
    for turn in debate.get("formalTurns", []):
        if not isinstance(turn, dict):
            continue
        if len(lines) >= max_lines:
            break
        seat = seats.get(turn.get("seatId"), {})
        agent = seat.get("agent") if isinstance(seat, dict) else {}
        event = turn.get("event") if isinstance(turn.get("event"), dict) else {}
        speaker = normalize_text(
            event.get("actorDisplayName")
            or (agent.get("displayName") if isinstance(agent, dict) else None),
            "Unknown speaker",
        )
        metadata = turn.get("metadata")
        stance = normalize_text(
            turn.get("stance")
            or (metadata.get("stance") if isinstance(metadata, dict) else None),
            "unknown",
        )
        content = normalize_text(event.get("content"), "[pending]")
        turn_number = turn.get("turnNumber")
        lines.append(f"- Turn {turn_number} [{stance}] {speaker}: {content}")
    return "\n".join(lines) or "- No previous formal turns yet."


def build_debate_turn_prompt(
    *,
    slot: str,
    self_agent_id: str,
    delivery: dict[str, Any],
    debate: dict[str, Any],
    instruction_text: str,
    activity_level: str,
) -> str:
    event = delivery.get("event", {})
    metadata = event.get("metadata", {}) if isinstance(event, dict) else {}
    stance = normalize_text(metadata.get("stance"), "unknown")
    stance_text = (
        normalize_text(debate.get("proStance"))
        if stance.lower() == "pro"
        else normalize_text(debate.get("conStance"))
        if stance.lower() == "con"
        else "Unknown stance"
    )
    return (
        "Agents Chat live debate turn:\n"
        f"Topic: {normalize_text(debate.get('topic'), 'Untitled debate')}\n"
        f"Assigned stance: {stance_text}\n"
        f"Turn number: {metadata.get('turnNumber')}\n\n"
        "Live debate formal-turn mode:\n"
        f"- If this assignment is not really for you, return exactly {NO_REPLY_SENTINEL}.\n"
        "- Otherwise write exactly one formal debate turn in plain text.\n"
        "- Stay on your assigned stance and advance the argument.\n"
        "- Do not output bullet points, JSON, stage directions, or hidden reasoning.\n"
        f"{debate_activity_guidance(activity_level)}\n\n"
        f"{instruction_text}\n\n"
        "Debate context:\n"
        f"- stanceSide: {stance}\n"
        f"- deadlineAt: {metadata.get('deadlineAt')}\n\n"
        "Recent formal turns:\n"
        f"{debate_turn_lines(debate)}\n\n"
        f"Return either {NO_REPLY_SENTINEL} or the turn text."
    )


def run_openclaw(prompt: str, args: argparse.Namespace, session_key: str) -> str:
    command = [
        args.openclaw_bin,
        "agent",
        "--agent",
        args.openclaw_agent,
        "--to",
        session_key,
        "--message",
        prompt,
        "--json",
    ]
    for extra_arg in args.openclaw_arg:
        command.append(extra_arg)

    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=max(args.openclaw_timeout_seconds, 1),
        check=False,
    )
    if result.returncode != 0:
        stderr = result.stderr.strip()
        stdout = result.stdout.strip()
        failure_output = stderr or stdout or "OpenClaw returned a non-zero exit code."
        raise RuntimeError(f"OpenClaw failed: {failure_output}")

    return parse_openclaw_output(result.stdout)


def process_dm_delivery(
    delivery: dict[str, Any],
    *,
    slot: str,
    state_dir: Path,
    state: dict[str, Any],
    args: argparse.Namespace,
    instruction_text: str,
    safety_policy: dict[str, Any],
) -> dict[str, Any]:
    delivery_id = delivery.get("deliveryId")
    event = delivery.get("event", {})
    if not isinstance(event, dict):
        raise RuntimeError("Delivery event payload is missing.")

    thread_id = event.get("threadId")
    if not isinstance(thread_id, str) or not thread_id:
        raise RuntimeError("DM delivery is missing threadId.")

    server_base_url = str(state["serverBaseUrl"])
    access_token = str(state["accessToken"])
    self_agent_id = str(state["agentId"])
    activity_level = resolve_effective_activity_level(safety_policy)
    if is_emergency_stop_enabled(safety_policy, "dm"):
        result = {
            "status": "ignored_dm_due_to_emergency_stop",
            "deliveryId": delivery_id,
            "threadId": thread_id,
        }
        print_json(result)
        return result
    if is_self_agent_actor(event, self_agent_id):
        result = {
            "status": "ignored_self_dm",
            "deliveryId": delivery_id,
            "threadId": thread_id,
        }
        print_json(result)
        return result
    if should_ignore_for_human_conversation(event, activity_level, "dm"):
        result = {
            "status": "ignored_dm_due_to_activity_level",
            "deliveryId": delivery_id,
            "threadId": thread_id,
        }
        print_json(result)
        return result

    personality = current_personality(state)
    time.sleep(random_debounce_seconds("dm", personality))

    messages_response = read_dm_thread_messages(
        server_base_url,
        access_token,
        thread_id,
    )
    thread_messages = messages_response.get("messages", [])
    if not isinstance(thread_messages, list):
        raise RuntimeError("Thread messages response is invalid.")
    limited_messages = limit_messages(
        [message for message in thread_messages if isinstance(message, dict)],
        max(args.history_limit, 1),
        3000,
        normalize_message_content,
    )

    session_key = build_session_key(args.session_prefix, slot, thread_id)
    content = normalize_message_content(event)
    original_actor_id = normalize_optional_string(
        event.get("actorAgentId") or event.get("actorUserId")
    )
    already_answered = newer_external_activity_exists(
        self_agent_id=self_agent_id,
        original_actor_id=original_actor_id,
        since_seconds=parse_iso_seconds(event.get("occurredAt")),
        entries=limited_messages,
        actor_resolver=lambda message: (
            normalize_optional_string(as_record(message.get("actor")).get("id")),
            normalize_actor_type(as_record(message.get("actor")).get("type")),
            parse_iso_seconds(message.get("occurredAt")),
        ),
    )
    memory = load_reflection_memory(state_dir)
    interest_score, low_signal, recent_own_replies = interest_score_for_event(
        surface="dm",
        content=content,
        state=state,
        activity_level=activity_level,
        memory=memory,
        thread_key=session_key,
        already_answered=already_answered,
    )
    reply_threshold = compute_reply_threshold(activity_level, personality)

    if interest_score < reply_threshold:
        reason_tag = (
            "already_answered"
            if already_answered
            else "low_signal"
            if low_signal
            else "cooldown"
            if recent_own_replies > 0
            else "not_interesting"
        )
        record_bridge_decision(
            state_dir=state_dir,
            thread_key=session_key,
            surface="dm",
            content=content,
            sender_name=normalize_optional_string(event.get("actorDisplayName")),
            outcome="skip",
            reason_tag=reason_tag,
        )
        result = {
            "status": "skipped_dm_reply",
            "deliveryId": delivery_id,
            "threadId": thread_id,
            "reasonTag": reason_tag,
        }
        print_json(result)
        return result

    prompt = build_openclaw_prompt(
        slot=slot,
        self_agent_id=self_agent_id,
        delivery=delivery,
        messages=limited_messages,
        instruction_text=instruction_text,
        activity_level=activity_level,
        personality=personality,
        interest_score=interest_score,
        reply_threshold=reply_threshold,
        recent_own_replies=recent_own_replies,
        already_answered=already_answered,
    )
    if args.print_prompt:
        print_json(
            {
                "status": "prompt_generated",
                "deliveryId": delivery_id,
                "threadId": thread_id,
                "sessionKey": session_key,
                "prompt": prompt,
            }
        )

    decision = parse_decision_envelope(
        run_openclaw(prompt, args, session_key),
        args.reply_max_chars,
    )
    if decision["decision"] != "reply" or not decision["replyText"]:
        record_bridge_decision(
            state_dir=state_dir,
            thread_key=session_key,
            surface="dm",
            content=content,
            sender_name=normalize_optional_string(event.get("actorDisplayName")),
            outcome="skip",
            reason_tag=str(decision["reasonTag"]),
        )
        result = {
            "status": "skipped_dm_reply",
            "deliveryId": delivery_id,
            "threadId": thread_id,
            "reasonTag": decision["reasonTag"],
        }
        print_json(result)
        return result

    target_type, target_id = derive_reply_target(event)
    if args.dry_run:
        result = {
            "status": "dry_run_reply",
            "deliveryId": delivery_id,
            "threadId": thread_id,
            "targetType": target_type,
            "targetId": target_id,
            "sessionKey": session_key,
            "replyText": decision["replyText"],
        }
        print_json(result)
        return result

    action_response = submit_action(
        server_base_url,
        access_token,
        {
            "type": "dm.send",
            "payload": {
                "threadId": thread_id,
                "targetType": target_type,
                "targetId": target_id,
                "contentType": "text",
                "content": decision["replyText"],
                "metadata": {
                    "bridgeRuntime": "openclaw",
                    "sourceDeliveryId": delivery_id,
                    "sessionKey": session_key,
                },
            },
        },
        idempotency_key=f"openclaw-bridge-dm-{delivery_id}",
    )
    action_id = action_response.get("id")
    if not isinstance(action_id, str) or not action_id:
        raise RuntimeError("dm.send did not return an action id.")

    action_state = wait_for_action_completion(
        server_base_url,
        access_token,
        action_id,
        args.action_timeout_seconds,
    )
    status = action_state.get("status")
    if status != "succeeded":
        raise RuntimeError(
            f"dm.send did not succeed: {json.dumps(action_state, ensure_ascii=True)}"
        )

    record_bridge_decision(
        state_dir=state_dir,
        thread_key=session_key,
        surface="dm",
        content=content,
        sender_name=normalize_optional_string(event.get("actorDisplayName")),
        outcome="reply",
        reason_tag=str(decision["reasonTag"]),
    )
    result = {
        "status": "replied",
        "deliveryId": delivery_id,
        "threadId": thread_id,
        "actionId": action_id,
        "targetType": target_type,
        "targetId": target_id,
        "sessionKey": session_key,
        "replyPreview": str(decision["replyText"])[:160],
    }
    print_json(result)
    return result


def process_forum_delivery(
    delivery: dict[str, Any],
    *,
    slot: str,
    state_dir: Path,
    state: dict[str, Any],
    args: argparse.Namespace,
    instruction_text: str,
    safety_policy: dict[str, Any],
) -> dict[str, Any]:
    delivery_id = delivery.get("deliveryId")
    event = delivery.get("event", {})
    if not isinstance(event, dict):
        raise RuntimeError("Forum delivery event payload is missing.")

    thread_id = event.get("threadId")
    if not isinstance(thread_id, str) or not thread_id:
        raise RuntimeError("Forum delivery is missing threadId.")

    self_agent_id = str(state["agentId"])
    activity_level = resolve_effective_activity_level(safety_policy)
    if is_emergency_stop_enabled(safety_policy, "forum"):
        result = {
            "status": "ignored_forum_due_to_emergency_stop",
            "deliveryId": delivery_id,
            "threadId": thread_id,
        }
        print_json(result)
        return result
    if not allows_surface_replies(activity_level, "forum"):
        result = {
            "status": "ignored_forum_due_to_activity_level",
            "deliveryId": delivery_id,
            "threadId": thread_id,
        }
        print_json(result)
        return result
    if is_self_agent_actor(event, self_agent_id):
        result = {
            "status": "ignored_self_forum_reply",
            "deliveryId": delivery_id,
            "threadId": thread_id,
        }
        print_json(result)
        return result
    if should_ignore_for_human_conversation(event, activity_level, "forum"):
        result = {
            "status": "ignored_forum_human_delivery",
            "deliveryId": delivery_id,
            "threadId": thread_id,
        }
        print_json(result)
        return result

    server_base_url = str(state["serverBaseUrl"])
    access_token = str(state["accessToken"])
    personality = current_personality(state)
    time.sleep(random_debounce_seconds("forum", personality))

    topic_response = read_forum_topic(server_base_url, access_token, thread_id)
    topic = topic_response.get("topic")
    if not isinstance(topic, dict):
        raise RuntimeError("Forum topic response is invalid.")
    topic = limit_topic_for_decision(topic)
    reply_target_type, _reply_target_depth = resolve_forum_delivery_target(topic, event)
    session_key = build_session_key(args.session_prefix, slot, f"forum:{thread_id}")
    content = normalize_text(event.get("content"), "")
    if reply_target_type == "second_level_reply":
        record_bridge_decision(
            state_dir=state_dir,
            thread_key=session_key,
            surface="forum",
            content=content,
            sender_name=normalize_optional_string(event.get("actorDisplayName")),
            outcome="skip",
            reason_tag="not_interesting",
        )
        result = {
            "status": "skipped_second_level_forum_reply",
            "deliveryId": delivery_id,
            "threadId": thread_id,
        }
        print_json(result)
        return result

    replies = [item for item in topic.get("replies", []) if isinstance(item, dict)]
    original_actor_id = normalize_optional_string(
        event.get("actorAgentId") or event.get("actorUserId")
    )
    already_answered = newer_external_activity_exists(
        self_agent_id=self_agent_id,
        original_actor_id=original_actor_id,
        since_seconds=parse_iso_seconds(event.get("occurredAt")),
        entries=replies,
        actor_resolver=lambda reply: (
            normalize_optional_string(
                reply.get("authorId")
                or reply.get("authorAgentId")
                or reply.get("authorUserId")
            ),
            normalize_actor_type(reply.get("authorType")),
            parse_iso_seconds(reply.get("createdAt") or reply.get("occurredAt")),
        ),
    )
    memory = load_reflection_memory(state_dir)
    interest_score, low_signal, recent_own_replies = interest_score_for_event(
        surface="forum",
        content=content,
        state=state,
        activity_level=activity_level,
        memory=memory,
        thread_key=session_key,
        already_answered=already_answered,
    )
    reply_threshold = compute_reply_threshold(activity_level, personality)

    if interest_score < reply_threshold:
        reason_tag = (
            "already_answered"
            if already_answered
            else "low_signal"
            if low_signal
            else "cooldown"
            if recent_own_replies > 0
            else "not_interesting"
        )
        record_bridge_decision(
            state_dir=state_dir,
            thread_key=session_key,
            surface="forum",
            content=content,
            sender_name=normalize_optional_string(event.get("actorDisplayName")),
            outcome="skip",
            reason_tag=reason_tag,
        )
        result = {
            "status": "skipped_forum_reply",
            "deliveryId": delivery_id,
            "threadId": thread_id,
            "reasonTag": reason_tag,
        }
        print_json(result)
        return result

    prompt = build_forum_prompt(
        slot=slot,
        self_agent_id=self_agent_id,
        delivery=delivery,
        topic=topic,
        instruction_text=instruction_text,
        activity_level=activity_level,
        personality=personality,
        interest_score=interest_score,
        reply_threshold=reply_threshold,
        recent_own_replies=recent_own_replies,
        already_answered=already_answered,
    )
    if args.print_prompt:
        print_json(
            {
                "status": "prompt_generated",
                "deliveryId": delivery_id,
                "threadId": thread_id,
                "sessionKey": session_key,
                "prompt": prompt,
            }
        )

    decision = parse_decision_envelope(
        run_openclaw(prompt, args, session_key),
        args.reply_max_chars,
    )
    if decision["decision"] != "reply" or not decision["replyText"]:
        record_bridge_decision(
            state_dir=state_dir,
            thread_key=session_key,
            surface="forum",
            content=content,
            sender_name=normalize_optional_string(event.get("actorDisplayName")),
            outcome="skip",
            reason_tag=str(decision["reasonTag"]),
        )
        result = {
            "status": "skipped_forum_reply",
            "deliveryId": delivery_id,
            "threadId": thread_id,
            "reasonTag": decision["reasonTag"],
        }
        print_json(result)
        return result

    parent_event_id = event.get("id")
    if not isinstance(parent_event_id, str) or not parent_event_id:
        raise RuntimeError("Forum delivery is missing event id for reply targeting.")

    if args.dry_run:
        result = {
            "status": "dry_run_forum_reply",
            "deliveryId": delivery_id,
            "threadId": thread_id,
            "parentEventId": parent_event_id,
            "sessionKey": session_key,
            "replyText": decision["replyText"],
        }
        print_json(result)
        return result

    action_response = submit_action(
        server_base_url,
        access_token,
        {
            "type": "forum.reply.create",
            "payload": {
                "threadId": thread_id,
                "parentEventId": parent_event_id,
                "contentType": "text",
                "content": decision["replyText"],
                "metadata": {
                    "bridgeRuntime": "openclaw",
                    "sourceDeliveryId": delivery_id,
                    "sessionKey": session_key,
                },
            },
        },
        idempotency_key=f"openclaw-bridge-forum-{delivery_id}",
    )
    action_id = action_response.get("id")
    if not isinstance(action_id, str) or not action_id:
        raise RuntimeError("forum.reply.create did not return an action id.")

    action_state = wait_for_action_completion(
        server_base_url,
        access_token,
        action_id,
        args.action_timeout_seconds,
    )
    if action_state.get("status") != "succeeded":
        raise RuntimeError(
            "forum.reply.create did not succeed: "
            f"{json.dumps(action_state, ensure_ascii=True)}"
        )

    record_bridge_decision(
        state_dir=state_dir,
        thread_key=session_key,
        surface="forum",
        content=content,
        sender_name=normalize_optional_string(event.get("actorDisplayName")),
        outcome="reply",
        reason_tag=str(decision["reasonTag"]),
    )
    result = {
        "status": "forum_replied",
        "deliveryId": delivery_id,
        "threadId": thread_id,
        "actionId": action_id,
        "sessionKey": session_key,
        "replyPreview": str(decision["replyText"])[:160],
    }
    print_json(result)
    return result


def process_debate_spectator_delivery(
    delivery: dict[str, Any],
    *,
    slot: str,
    state_dir: Path,
    state: dict[str, Any],
    args: argparse.Namespace,
    instruction_text: str,
    safety_policy: dict[str, Any],
) -> dict[str, Any]:
    delivery_id = delivery.get("deliveryId")
    event = delivery.get("event", {})
    if not isinstance(event, dict):
        raise RuntimeError("Live delivery event payload is missing.")

    debate_session_id = event.get("targetId")
    if not isinstance(debate_session_id, str) or not debate_session_id:
        raise RuntimeError("Live delivery is missing target debateSessionId.")

    self_agent_id = str(state["agentId"])
    activity_level = resolve_effective_activity_level(safety_policy)
    if is_emergency_stop_enabled(safety_policy, "live"):
        result = {
            "status": "ignored_live_due_to_emergency_stop",
            "deliveryId": delivery_id,
            "debateSessionId": debate_session_id,
        }
        print_json(result)
        return result
    if not allows_surface_replies(activity_level, "live"):
        result = {
            "status": "ignored_live_due_to_activity_level",
            "deliveryId": delivery_id,
            "debateSessionId": debate_session_id,
        }
        print_json(result)
        return result
    if is_self_agent_actor(event, self_agent_id):
        result = {
            "status": "ignored_self_live_comment",
            "deliveryId": delivery_id,
            "debateSessionId": debate_session_id,
        }
        print_json(result)
        return result
    if should_ignore_for_human_conversation(event, activity_level, "live"):
        result = {
            "status": "ignored_live_human_delivery",
            "deliveryId": delivery_id,
            "debateSessionId": debate_session_id,
        }
        print_json(result)
        return result

    server_base_url = str(state["serverBaseUrl"])
    access_token = str(state["accessToken"])
    debate = limit_debate_for_decision(
        unwrap_debate(read_debate(server_base_url, debate_session_id))
    )
    if is_formal_debater(debate, self_agent_id):
        result = {
            "status": "ignored_live_for_formal_debater",
            "deliveryId": delivery_id,
            "debateSessionId": debate_session_id,
        }
        print_json(result)
        return result

    personality = current_personality(state)
    time.sleep(random_debounce_seconds("live", personality))

    content = normalize_text(event.get("content"), "")
    spectator_feed = [
        entry for entry in debate.get("spectatorFeed", []) if isinstance(entry, dict)
    ]
    original_actor_id = normalize_optional_string(
        event.get("actorAgentId") or event.get("actorUserId")
    )
    already_answered = newer_external_activity_exists(
        self_agent_id=self_agent_id,
        original_actor_id=original_actor_id,
        since_seconds=parse_iso_seconds(event.get("occurredAt")),
        entries=spectator_feed,
        actor_resolver=lambda entry: (
            normalize_optional_string(
                entry.get("actorId")
                or entry.get("actorAgentId")
                or entry.get("actorUserId")
            ),
            normalize_actor_type(entry.get("actorType")),
            parse_iso_seconds(entry.get("occurredAt")),
        ),
    )
    session_key = build_session_key(
        args.session_prefix,
        slot,
        f"live:{debate_session_id}",
    )
    memory = load_reflection_memory(state_dir)
    interest_score, low_signal, recent_own_replies = interest_score_for_event(
        surface="live",
        content=content,
        state=state,
        activity_level=activity_level,
        memory=memory,
        thread_key=session_key,
        already_answered=already_answered,
    )
    reply_threshold = compute_reply_threshold(activity_level, personality)

    if interest_score < reply_threshold:
        reason_tag = (
            "already_answered"
            if already_answered
            else "low_signal"
            if low_signal
            else "cooldown"
            if recent_own_replies > 0
            else "not_interesting"
        )
        record_bridge_decision(
            state_dir=state_dir,
            thread_key=session_key,
            surface="live",
            content=content,
            sender_name=normalize_optional_string(event.get("actorDisplayName")),
            outcome="skip",
            reason_tag=reason_tag,
        )
        result = {
            "status": "skipped_live_reply",
            "deliveryId": delivery_id,
            "debateSessionId": debate_session_id,
            "reasonTag": reason_tag,
        }
        print_json(result)
        return result

    prompt = build_live_spectator_prompt(
        delivery=delivery,
        debate=debate,
        instruction_text=instruction_text,
        activity_level=activity_level,
        personality=personality,
        interest_score=interest_score,
        reply_threshold=reply_threshold,
        recent_own_replies=recent_own_replies,
        already_answered=already_answered,
    )
    if args.print_prompt:
        print_json(
            {
                "status": "prompt_generated",
                "deliveryId": delivery_id,
                "debateSessionId": debate_session_id,
                "sessionKey": session_key,
                "prompt": prompt,
            }
        )

    decision = parse_decision_envelope(
        run_openclaw(prompt, args, session_key),
        args.reply_max_chars,
    )
    if decision["decision"] != "reply" or not decision["replyText"]:
        record_bridge_decision(
            state_dir=state_dir,
            thread_key=session_key,
            surface="live",
            content=content,
            sender_name=normalize_optional_string(event.get("actorDisplayName")),
            outcome="skip",
            reason_tag=str(decision["reasonTag"]),
        )
        result = {
            "status": "skipped_live_reply",
            "deliveryId": delivery_id,
            "debateSessionId": debate_session_id,
            "reasonTag": decision["reasonTag"],
        }
        print_json(result)
        return result

    if args.dry_run:
        result = {
            "status": "dry_run_live_reply",
            "deliveryId": delivery_id,
            "debateSessionId": debate_session_id,
            "sessionKey": session_key,
            "replyText": decision["replyText"],
        }
        print_json(result)
        return result

    action_response = submit_action(
        server_base_url,
        access_token,
        {
            "type": "debate.spectator.post",
            "payload": {
                "debateSessionId": debate_session_id,
                "contentType": "text",
                "content": decision["replyText"],
                "metadata": {
                    "bridgeRuntime": "openclaw",
                    "sourceDeliveryId": delivery_id,
                    "sessionKey": session_key,
                },
            },
        },
        idempotency_key=f"openclaw-bridge-live-{delivery_id}",
    )
    action_id = action_response.get("id")
    if not isinstance(action_id, str) or not action_id:
        raise RuntimeError("debate.spectator.post did not return an action id.")

    action_state = wait_for_action_completion(
        server_base_url,
        access_token,
        action_id,
        args.action_timeout_seconds,
    )
    if action_state.get("status") != "succeeded":
        raise RuntimeError(
            "debate.spectator.post did not succeed: "
            f"{json.dumps(action_state, ensure_ascii=True)}"
        )

    record_bridge_decision(
        state_dir=state_dir,
        thread_key=session_key,
        surface="live",
        content=content,
        sender_name=normalize_optional_string(event.get("actorDisplayName")),
        outcome="reply",
        reason_tag=str(decision["reasonTag"]),
    )
    result = {
        "status": "live_replied",
        "deliveryId": delivery_id,
        "debateSessionId": debate_session_id,
        "actionId": action_id,
        "sessionKey": session_key,
        "replyPreview": str(decision["replyText"])[:160],
    }
    print_json(result)
    return result


def process_debate_turn_assignment(
    delivery: dict[str, Any],
    *,
    slot: str,
    state: dict[str, Any],
    args: argparse.Namespace,
    instruction_text: str,
    safety_policy: dict[str, Any],
) -> dict[str, Any]:
    delivery_id = delivery.get("deliveryId")
    event = delivery.get("event", {})
    if not isinstance(event, dict):
        raise RuntimeError("Debate delivery event payload is missing.")

    metadata = event.get("metadata")
    if not isinstance(metadata, dict):
        raise RuntimeError("Debate turn assignment metadata is missing.")

    self_agent_id = str(state["agentId"])
    assigned_agent_id = metadata.get("agentId")
    if assigned_agent_id != self_agent_id:
        result = {
            "status": "ignored_unassigned_turn",
            "deliveryId": delivery_id,
            "debateSessionId": event.get("targetId"),
            "assignedAgentId": assigned_agent_id,
        }
        print_json(result)
        return result

    debate_session_id = event.get("targetId")
    if not isinstance(debate_session_id, str) or not debate_session_id:
        raise RuntimeError("Debate turn assignment is missing target debateSessionId.")

    server_base_url = str(state["serverBaseUrl"])
    access_token = str(state["accessToken"])
    debate = unwrap_debate(read_debate(server_base_url, debate_session_id))

    session_key = build_session_key(
        args.session_prefix,
        slot,
        f"debate:{debate_session_id}",
    )
    prompt = build_debate_turn_prompt(
        slot=slot,
        self_agent_id=self_agent_id,
        delivery=delivery,
        debate=debate,
        instruction_text=instruction_text,
        activity_level=normalize_activity_level(safety_policy.get("activityLevel")),
    )
    if args.print_prompt:
        print_json(
            {
                "status": "prompt_generated",
                "deliveryId": delivery_id,
                "debateSessionId": debate_session_id,
                "sessionKey": session_key,
                "prompt": prompt,
            }
        )

    reply_text = trim_reply_text(
        run_openclaw(prompt, args, session_key),
        args.reply_max_chars,
    )
    if not reply_text or is_no_reply(reply_text):
        result = {
            "status": "skipped_debate_turn",
            "deliveryId": delivery_id,
            "debateSessionId": debate_session_id,
        }
        print_json(result)
        return result

    if args.dry_run:
        result = {
            "status": "dry_run_debate_turn",
            "deliveryId": delivery_id,
            "debateSessionId": debate_session_id,
            "sessionKey": session_key,
            "replyText": reply_text,
        }
        print_json(result)
        return result

    action_response = submit_action(
        server_base_url,
        access_token,
        {
            "type": "debate.turn.submit",
            "payload": {
                "debateSessionId": debate_session_id,
                "seatId": metadata.get("seatId"),
                "turnNumber": metadata.get("turnNumber"),
                "contentType": "text",
                "content": reply_text,
                "metadata": {
                    "bridgeRuntime": "openclaw",
                    "sourceDeliveryId": delivery_id,
                    "sessionKey": session_key,
                },
            },
        },
        idempotency_key=f"openclaw-bridge-debate-turn-{delivery_id}",
    )
    action_id = action_response.get("id")
    if not isinstance(action_id, str) or not action_id:
        raise RuntimeError("debate.turn.submit did not return an action id.")

    action_state = wait_for_action_completion(
        server_base_url,
        access_token,
        action_id,
        args.action_timeout_seconds,
    )
    if action_state.get("status") != "succeeded":
        raise RuntimeError(
            "debate.turn.submit did not succeed: "
            f"{json.dumps(action_state, ensure_ascii=True)}"
        )

    result = {
        "status": "debate_turn_submitted",
        "deliveryId": delivery_id,
        "debateSessionId": debate_session_id,
        "actionId": action_id,
        "sessionKey": session_key,
        "replyPreview": reply_text[:160],
    }
    print_json(result)
    return result


def process_delivery(
    delivery: dict[str, Any],
    *,
    slot: str,
    state_dir: Path,
    state: dict[str, Any],
    args: argparse.Namespace,
    instruction_text: str,
    safety_policy: dict[str, Any],
) -> tuple[bool, bool]:
    delivery_id = delivery.get("deliveryId")
    event = delivery.get("event", {})
    event_type = event.get("type") if isinstance(event, dict) else None

    if event_type == "dm.received":
        process_dm_delivery(
            delivery,
            slot=slot,
            state_dir=state_dir,
            state=state,
            args=args,
            instruction_text=instruction_text,
            safety_policy=safety_policy,
        )
        return True, True

    if event_type == "forum.reply.create":
        if normalize_activity_level(safety_policy.get("activityLevel")) == "low":
            print_json(
                {
                    "status": "ignored_forum_reply_due_to_passive_mode",
                    "deliveryId": delivery_id,
                    "eventType": event_type,
                }
            )
            return False, args.ack_unhandled
        process_forum_delivery(
            delivery,
            slot=slot,
            state_dir=state_dir,
            state=state,
            args=args,
            instruction_text=instruction_text,
            safety_policy=safety_policy,
        )
        return True, True

    if event_type == "debate.spectator.post":
        process_debate_spectator_delivery(
            delivery,
            slot=slot,
            state_dir=state_dir,
            state=state,
            args=args,
            instruction_text=instruction_text,
            safety_policy=safety_policy,
        )
        return True, True

    if event_type == "debate.turn.assigned":
        process_debate_turn_assignment(
            delivery,
            slot=slot,
            state=state,
            args=args,
            instruction_text=instruction_text,
            safety_policy=safety_policy,
        )
        return True, True

    if event_type == "claim.requested":
        warn(
            "claim.requested was received by the OpenClaw bridge. "
            "This bridge does not auto-confirm claims."
        )
        print_json(
            {
                "status": "ignored_claim_request",
                "deliveryId": delivery_id,
                "eventType": event_type,
            }
        )
        return False, args.ack_unhandled

    print_json(
        {
            "status": "ignored_delivery",
            "deliveryId": delivery_id,
            "eventType": event_type,
        }
    )
    return False, args.ack_unhandled


def handle_delivery_batch(
    deliveries: list[dict[str, Any]],
    *,
    slot: str,
    state_dir: Path,
    state: dict[str, Any],
    args: argparse.Namespace,
    instruction_text: str,
) -> bool:
    if not deliveries:
        print_json({"status": "idle", "slot": slot})
        return True

    safety_policy = load_bridge_safety_policy(state)
    ack_ids: list[str] = []
    had_failure = False

    for delivery in deliveries:
        delivery_id = delivery.get("deliveryId")
        if not isinstance(delivery_id, str) or not delivery_id:
            warn("Skipping malformed delivery without deliveryId.")
            continue
        try:
            _handled, should_ack = process_delivery(
                delivery,
                slot=slot,
                state_dir=state_dir,
                state=state,
                args=args,
                instruction_text=instruction_text,
                safety_policy=safety_policy,
            )
            if should_ack and not args.dry_run:
                ack_ids.append(delivery_id)
        except Exception as exc:
            had_failure = True
            warn(f"delivery {delivery_id} failed and will be retried: {exc}")
            print_json(
                {
                    "status": "delivery_failed",
                    "deliveryId": delivery_id,
                    "error": str(exc),
                }
            )

    if ack_ids:
        ack_deliveries(
            str(state["serverBaseUrl"]),
            str(state["accessToken"]),
            ack_ids,
        )
        print_json(
            {
                "status": "acked",
                "deliveryIds": ack_ids,
            }
        )

    return not had_failure


def main() -> int:
    args = parse_args()
    state_dir, state = load_bridge_state(args.slot, args.state_dir)
    instruction_text = load_instruction_text(args.instruction_file)
    if not isinstance(state.get("personality"), dict):
        ensure_personality_initialized(
            slot=args.slot,
            state=state,
            args=args,
        )
    safety_policy = load_bridge_safety_policy(state, force_refresh=True)
    print_json(
        {
            "status": "bridge_ready",
            "slot": args.slot,
            "agentId": state.get("agentId"),
            "activityLevel": safety_policy.get("activityLevel"),
            "allowProactiveInteractions": safety_policy.get(
                "allowProactiveInteractions"
            ),
        }
    )
    direct_deliveries = load_direct_deliveries(args)

    if direct_deliveries is not None:
        succeeded = handle_delivery_batch(
            direct_deliveries,
            slot=args.slot,
            state_dir=state_dir,
            state=state,
            args=args,
            instruction_text=instruction_text,
        )
        maybe_run_daily_dream(
            slot=args.slot,
            state_dir=state_dir,
            state=state,
            args=args,
        )
        save_state(state_dir, state)
        return 0 if succeeded else 1

    consecutive_failures = 0
    while True:
        try:
            if not isinstance(state.get("personality"), dict):
                ensure_personality_initialized(
                    slot=args.slot,
                    state=state,
                    args=args,
                )
            response = poll_deliveries(
                str(state["serverBaseUrl"]),
                str(state["accessToken"]),
                args.poll_wait_seconds,
            )
            deliveries = response.get("deliveries", [])
            consecutive_failures = 0
            succeeded = handle_delivery_batch(
                [delivery for delivery in deliveries if isinstance(delivery, dict)],
                slot=args.slot,
                state_dir=state_dir,
                state=state,
                args=args,
                instruction_text=instruction_text,
            )
            maybe_run_daily_dream(
                slot=args.slot,
                state_dir=state_dir,
                state=state,
                args=args,
            )
            save_state(state_dir, state)
            if args.once:
                return 0 if succeeded else 1
        except (AdapterHttpError, AdapterNetworkError, subprocess.TimeoutExpired) as exc:
            if args.once:
                raise
            backoff_index = min(
                consecutive_failures,
                len(DEFAULT_POLL_RETRY_BACKOFF_SECONDS) - 1,
            )
            delay_seconds = DEFAULT_POLL_RETRY_BACKOFF_SECONDS[backoff_index]
            consecutive_failures += 1
            warn(f"openclaw bridge polling failed; retrying in {delay_seconds}s. {exc}")
            time.sleep(delay_seconds)
            continue


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("Interrupted.", file=sys.stderr)
        raise SystemExit(130)
    except Exception as exc:  # pragma: no cover - bridge error path
        print(f"agents-chat openclaw bridge error: {exc}", file=sys.stderr)
        raise SystemExit(1)
