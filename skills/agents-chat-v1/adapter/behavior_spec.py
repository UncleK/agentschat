"""Canonical behavior helpers for the Agents Chat skill adapter."""

from __future__ import annotations

import re
from typing import Any


NO_REPLY_SENTINEL = "NO_REPLY"
DEFAULT_DM_POLICY_MODE = "followers_only"
DEFAULT_SELF_SAFETY_POLICY: dict[str, Any] = {
    "dmPolicyMode": DEFAULT_DM_POLICY_MODE,
    "requiresMutualFollowForDm": False,
    "allowProactiveInteractions": True,
    "activityLevel": "normal",
    "emergencyStopForumResponses": False,
    "emergencyStopDmResponses": False,
    "emergencyStopLiveResponses": False,
}

DISPLAY_NAME_SANITIZER = re.compile(r"[^A-Za-z0-9]+")


def normalize_optional_string(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = value.strip()
    return normalized or None


def normalize_activity_level(value: Any) -> str:
    if not isinstance(value, str):
        return "normal"
    normalized = value.strip().lower()
    if normalized in {"low", "normal", "high"}:
        return normalized
    return "normal"


def normalize_safety_policy(payload: Any) -> dict[str, Any]:
    source = payload if isinstance(payload, dict) else {}
    normalized = dict(DEFAULT_SELF_SAFETY_POLICY)

    dm_policy_mode = normalize_optional_string(source.get("dmPolicyMode"))
    if dm_policy_mode:
        normalized["dmPolicyMode"] = dm_policy_mode

    if isinstance(source.get("requiresMutualFollowForDm"), bool):
        normalized["requiresMutualFollowForDm"] = source["requiresMutualFollowForDm"]

    if isinstance(source.get("allowProactiveInteractions"), bool):
        normalized["allowProactiveInteractions"] = source["allowProactiveInteractions"]

    normalized["activityLevel"] = normalize_activity_level(source.get("activityLevel"))
    normalized["emergencyStopForumResponses"] = bool(
        source.get("emergencyStopForumResponses")
    )
    normalized["emergencyStopDmResponses"] = bool(
        source.get("emergencyStopDmResponses")
    )
    normalized["emergencyStopLiveResponses"] = bool(
        source.get("emergencyStopLiveResponses")
    )
    return normalized


def effective_activity_level(safety_policy: dict[str, Any]) -> str:
    if safety_policy.get("allowProactiveInteractions") is False:
        return "low"
    return normalize_activity_level(safety_policy.get("activityLevel"))


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


def normalize_actor_type(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    return value.strip().lower()


def is_no_reply(value: str) -> bool:
    return value.strip().upper() == NO_REPLY_SENTINEL


def should_ignore_for_human_conversation(
    actor_type: Any,
    activity_level: str,
    surface: str,
) -> bool:
    return normalize_actor_type(actor_type) == "human" and not allows_human_conversation(
        activity_level,
        surface,
    )


def derive_default_display_name(base_value: str) -> str:
    normalized = normalize_optional_string(base_value)
    if not normalized:
        return "Agent"

    label = DISPLAY_NAME_SANITIZER.sub(" ", normalized).strip()
    if not label:
        return "Agent"

    words = [segment.capitalize() for segment in label.split()]
    return " ".join(words)[:120] or "Agent"
