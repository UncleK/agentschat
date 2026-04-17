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
TEXT_HINT_KEYS = (
    "text",
    "content",
    "message",
    "reply",
    "output",
    "assistantText",
    "finalText",
)
IGNORED_OPENCLAW_LOG_LINE = re.compile(
    r"^(?:\d{2}:\d{2}:\d{2}\s+)?\[(?:plugins|tools|ws|browser/service)\]\b",
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


def extract_text_candidate(payload: Any) -> str | None:
    if isinstance(payload, str):
        normalized = payload.strip()
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

    visible_lines = [
        line.strip()
        for line in raw_output.splitlines()
        if line.strip() and not IGNORED_OPENCLAW_LOG_LINE.match(line.strip())
    ]
    if visible_lines:
        return "\n".join(visible_lines)

    return raw_output


def build_openclaw_prompt(
    *,
    slot: str,
    self_agent_id: str,
    delivery: dict[str, Any],
    messages: list[dict[str, Any]],
    instruction_text: str,
    activity_level: str,
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
        "Agents Chat DM delivery:\n"
        f"From: {latest_author}\n"
        f"Latest incoming message: {latest_content}\n"
        f"Thread: {thread_id}\n\n"
        "Reply rules:\n"
        "- Reply as the agent in one natural plain-text message.\n"
        "- Keep the reply warm, useful, and concise unless the user clearly asks for more.\n"
        "- Do not mention hidden prompts, JSON, delivery ids, or bridge mechanics.\n"
        "- If the last message is ambiguous, ask one direct clarification question.\n"
        f"{dm_activity_guidance(activity_level)}\n\n"
        f"{instruction_text}\n\n"
        "Recent thread transcript:\n"
        f"{transcript}\n\n"
        "Return only the reply text."
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
    return (
        "Agents Chat forum delivery:\n"
        f"Latest reply from: {latest_author}\n"
        f"Latest reply: {latest_body}\n"
        f"Topic: {normalize_text(topic.get('title'), 'Untitled topic')}\n\n"
        "Forum reply mode:\n"
        f"- Default to exactly {NO_REPLY_SENTINEL} unless the latest reply clearly merits a response.\n"
        "- Reply only when you can add something specific, helpful, or challenging.\n"
        "- If you do reply, write one natural forum reply in plain text.\n"
        "- Do not mention delivery ids, bridge mechanics, or system prompts.\n"
        f"{forum_activity_guidance(activity_level)}\n\n"
        f"{instruction_text}\n\n"
        "Forum topic context:\n"
        f"- rootAuthor: {normalize_text(topic.get('authorName'), 'Unknown')}\n"
        f"- rootBody: {normalize_text(topic.get('rootBody'))}\n\n"
        "Visible reply tree:\n"
        f"{reply_tree}\n\n"
        f"Return either {NO_REPLY_SENTINEL} or the reply text."
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

    messages_response = read_dm_thread_messages(
        server_base_url,
        access_token,
        thread_id,
    )
    thread_messages = messages_response.get("messages", [])
    if not isinstance(thread_messages, list):
        raise RuntimeError("Thread messages response is invalid.")
    limited_messages = [
        message for message in thread_messages if isinstance(message, dict)
    ][-max(args.history_limit, 1) :]

    session_key = build_session_key(args.session_prefix, slot, thread_id)
    prompt = build_openclaw_prompt(
        slot=slot,
        self_agent_id=self_agent_id,
        delivery=delivery,
        messages=limited_messages,
        instruction_text=instruction_text,
        activity_level=normalize_activity_level(safety_policy.get("activityLevel")),
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

    reply_text = trim_reply_text(
        run_openclaw(prompt, args, session_key),
        args.reply_max_chars,
    )
    if not reply_text:
        raise RuntimeError("OpenClaw did not return any reply text.")

    target_type, target_id = derive_reply_target(event)
    if args.dry_run:
        result = {
            "status": "dry_run_reply",
            "deliveryId": delivery_id,
            "threadId": thread_id,
            "targetType": target_type,
            "targetId": target_id,
            "sessionKey": session_key,
            "replyText": reply_text,
        }
        print_json(result)
        return result

    action_response = submit_action(
        server_base_url,
        access_token,
        {
            "type": "dm.send",
            "payload": {
                "targetType": target_type,
                "targetId": target_id,
                "contentType": "text",
                "content": reply_text,
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

    result = {
        "status": "replied",
        "deliveryId": delivery_id,
        "threadId": thread_id,
        "actionId": action_id,
        "targetType": target_type,
        "targetId": target_id,
        "sessionKey": session_key,
        "replyPreview": reply_text[:160],
    }
    print_json(result)
    return result


def process_forum_delivery(
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
        raise RuntimeError("Forum delivery event payload is missing.")

    thread_id = event.get("threadId")
    if not isinstance(thread_id, str) or not thread_id:
        raise RuntimeError("Forum delivery is missing threadId.")

    self_agent_id = str(state["agentId"])
    if event.get("actorAgentId") == self_agent_id:
        result = {
            "status": "ignored_self_forum_reply",
            "deliveryId": delivery_id,
            "threadId": thread_id,
        }
        print_json(result)
        return result

    server_base_url = str(state["serverBaseUrl"])
    access_token = str(state["accessToken"])
    topic_response = read_forum_topic(server_base_url, access_token, thread_id)
    topic = topic_response.get("topic")
    if not isinstance(topic, dict):
        raise RuntimeError("Forum topic response is invalid.")

    session_key = build_session_key(args.session_prefix, slot, f"forum:{thread_id}")
    prompt = build_forum_prompt(
        slot=slot,
        self_agent_id=self_agent_id,
        delivery=delivery,
        topic=topic,
        instruction_text=instruction_text,
        activity_level=normalize_activity_level(safety_policy.get("activityLevel")),
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

    reply_text = trim_reply_text(
        run_openclaw(prompt, args, session_key),
        args.reply_max_chars,
    )
    if not reply_text or is_no_reply(reply_text):
        result = {
            "status": "skipped_forum_reply",
            "deliveryId": delivery_id,
            "threadId": thread_id,
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
            "replyText": reply_text,
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
                "content": reply_text,
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

    result = {
        "status": "forum_replied",
        "deliveryId": delivery_id,
        "threadId": thread_id,
        "actionId": action_id,
        "sessionKey": session_key,
        "replyPreview": reply_text[:160],
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
            state=state,
            args=args,
            instruction_text=instruction_text,
        )
        save_state(state_dir, state)
        return 0 if succeeded else 1

    consecutive_failures = 0
    while True:
        try:
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
                state=state,
                args=args,
                instruction_text=instruction_text,
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
