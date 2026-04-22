#!/usr/bin/env python3
"""Generic host-runtime driver for the Agents Chat skill worker."""

from __future__ import annotations

import json
import re
import subprocess
import uuid
from typing import Any

from behavior_spec import is_no_reply
from bridge_personality import parse_decision_envelope, trim_text


HOST_STDIO_CONTRACT_VERSION = "agents-chat-host-stdio-v1"
TEXT_HINT_KEYS = (
    "replyText",
    "turnText",
    "text",
    "content",
    "message",
    "output",
    "finalText",
    "assistantText",
)
PROFILE_HINT_KEYS = (
    "summary",
    "warmth",
    "curiosity",
    "restraint",
    "cadence",
    "autoEvolve",
    "lastDreamedAt",
)
JSON_OBJECT_PATTERN = re.compile(r"\{[\s\S]*\}")


class HostRuntimeDriverError(RuntimeError):
    """Raised when the host runtime contract fails."""


def as_record(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def normalize_optional_string(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = value.strip()
    return normalized or None


def _extract_json_object(text: str) -> dict[str, Any] | None:
    normalized = text.strip()
    if not normalized:
        return None
    try:
        parsed = json.loads(normalized)
    except json.JSONDecodeError:
        parsed = None
    if isinstance(parsed, dict):
        return parsed

    match = JSON_OBJECT_PATTERN.search(normalized)
    if not match:
        return None
    try:
        parsed = json.loads(match.group(0))
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


def _unwrap_response(parsed: dict[str, Any]) -> dict[str, Any]:
    if isinstance(parsed.get("ok"), bool) and not parsed["ok"]:
        message = (
            normalize_optional_string(parsed.get("error"))
            or normalize_optional_string(parsed.get("message"))
            or "host runtime returned ok=false"
        )
        raise HostRuntimeDriverError(message)

    result = parsed.get("result")
    if isinstance(result, dict):
        return result
    return parsed


def _pick_text(payload: dict[str, Any]) -> str | None:
    for key in TEXT_HINT_KEYS:
        value = normalize_optional_string(payload.get(key))
        if value is not None:
            return value
    return None


def _normalize_reply_payload(
    payload: dict[str, Any],
    max_chars: int,
) -> dict[str, Any] | None:
    candidate = as_record(payload.get("decision")) or payload
    decision = normalize_optional_string(candidate.get("decision"))
    reason_tag = normalize_optional_string(candidate.get("reasonTag")) or "useful"
    reply_text = _pick_text(candidate)

    if decision in {"reply", "skip"}:
        if decision == "skip":
            return {
                "decision": "skip",
                "reasonTag": reason_tag,
                "replyText": "",
            }
        if not reply_text or is_no_reply(reply_text):
            return {
                "decision": "skip",
                "reasonTag": reason_tag,
                "replyText": "",
            }
        return {
            "decision": "reply",
            "reasonTag": reason_tag,
            "replyText": trim_text(reply_text, max_chars),
        }

    if reply_text is None:
        return None
    if is_no_reply(reply_text):
        return {
            "decision": "skip",
            "reasonTag": "not_interesting",
            "replyText": "",
        }
    return {
        "decision": "reply",
        "reasonTag": reason_tag,
        "replyText": trim_text(reply_text, max_chars),
    }


class HostRuntimeDriver:
    """Invoke a host runtime over the shared JSON stdin/stdout contract."""

    def __init__(
        self,
        *,
        host_command: str,
        host_args: list[str] | None = None,
        timeout_seconds: int = 180,
        workdir: str | None = None,
    ) -> None:
        normalized_command = normalize_optional_string(host_command)
        if not normalized_command:
            raise ValueError("host_command must be non-empty.")
        self.host_command = normalized_command
        self.host_args = list(host_args or [])
        self.timeout_seconds = max(int(timeout_seconds), 1)
        self.workdir = workdir

    def _command(self) -> list[str]:
        return [self.host_command, *self.host_args]

    def _run(self, *, action: str, session_key: str, input_payload: dict[str, Any]) -> str:
        request_payload = {
            "version": HOST_STDIO_CONTRACT_VERSION,
            "requestId": str(uuid.uuid4()),
            "action": action,
            "sessionKey": session_key,
            "input": input_payload,
        }
        try:
            result = subprocess.run(
                self._command(),
                input=json.dumps(request_payload, ensure_ascii=True),
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=self.timeout_seconds,
                check=False,
                cwd=self.workdir,
            )
        except subprocess.TimeoutExpired as exc:
            raise HostRuntimeDriverError(
                f"host runtime timed out after {self.timeout_seconds}s"
            ) from exc

        if result.returncode != 0:
            failure_output = (
                normalize_optional_string(result.stderr)
                or normalize_optional_string(result.stdout)
                or "host runtime returned a non-zero exit code"
            )
            raise HostRuntimeDriverError(failure_output)
        return result.stdout

    def invoke_profile_bootstrap(
        self,
        *,
        session_key: str,
        input_payload: dict[str, Any],
    ) -> dict[str, Any]:
        raw_output = self._run(
            action="profile_bootstrap",
            session_key=session_key,
            input_payload=input_payload,
        )
        parsed = _extract_json_object(raw_output)
        if parsed is None:
            raise HostRuntimeDriverError(
                "host runtime did not return JSON for profile_bootstrap"
            )

        payload = _unwrap_response(parsed)
        profile_draft = as_record(payload.get("profileDraft"))
        if not profile_draft and any(key in payload for key in PROFILE_HINT_KEYS):
            profile_draft = payload
        if not profile_draft:
            personality = as_record(payload.get("personality"))
            if any(key in personality for key in PROFILE_HINT_KEYS):
                profile_draft = personality
        if not profile_draft:
            raise HostRuntimeDriverError(
                "host runtime response did not include profileDraft"
            )
        return profile_draft

    def invoke_reply_or_turn(
        self,
        *,
        session_key: str,
        input_payload: dict[str, Any],
        max_chars: int,
    ) -> dict[str, Any]:
        raw_output = self._run(
            action="reply_or_turn",
            session_key=session_key,
            input_payload=input_payload,
        )
        parsed = _extract_json_object(raw_output)
        if parsed is not None:
            normalized = _normalize_reply_payload(_unwrap_response(parsed), max_chars)
            if normalized is not None:
                return normalized
        return parse_decision_envelope(raw_output, max_chars)
