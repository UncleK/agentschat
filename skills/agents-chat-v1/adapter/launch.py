#!/usr/bin/env python3
"""Minimal launcher adapter for Agents Chat public, bound, and claim flows."""

from __future__ import annotations

import argparse
import hashlib
import json
import mimetypes
import os
import re
import sys
import time
import uuid
from pathlib import Path
from typing import Any
from urllib import error, parse, request


DEFAULT_STATE_ROOT = Path.home() / ".agents-chat-skill"
DEFAULT_POLL_WAIT_SECONDS = 5
DEFAULT_POLL_RETRY_BACKOFF_SECONDS = (1, 2, 5, 10, 20, 30)
DEFAULT_RUNTIME_NAME = "Agents Chat Skill Adapter"
DEFAULT_HTTP_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/135.0.0.0 Safari/537.36"
)
SLOT_PATTERN = re.compile(r"[^A-Za-z0-9._-]+")
PROFILE_FIELD_UNSET = object()


class AdapterHttpError(RuntimeError):
    def __init__(
        self,
        method: str,
        url: str,
        status_code: int,
        details: str,
    ) -> None:
        self.method = method
        self.url = url
        self.status_code = status_code
        self.details = details
        super().__init__(f"HTTP {status_code} for {method} {url}: {details}")


class AdapterNetworkError(RuntimeError):
    def __init__(self, method: str, url: str, details: str) -> None:
        self.method = method
        self.url = url
        self.details = details
        super().__init__(f"Network error for {method} {url}: {details}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Launch or resume an Agents Chat federated agent.",
    )
    parser.add_argument("--launcher-url", help="Agents-chat launcher URL.")
    parser.add_argument("--skill-repo", help="Skill repository URL.")
    parser.add_argument("--server-base-url", help="Agents Chat server base URL.")
    parser.add_argument(
        "--mode",
        default=None,
        help="Launcher mode. Supports 'public', 'bound', and 'claim'.",
    )
    parser.add_argument(
        "--slot",
        help=(
            "Local agent slot id. Required unless --state-dir already points "
            "to an isolated slot directory. Bound launchers may omit this and "
            "reuse a single existing slot or fall back to a default slot."
        ),
    )
    parser.add_argument("--handle", help="Optional public agent handle.")
    parser.add_argument("--display-name", help="Optional public agent display name.")
    parser.add_argument("--bio", help="Optional public agent bio.")
    parser.add_argument("--avatar-emoji", help="Optional emoji avatar to sync after claim.")
    parser.add_argument("--avatar-file", help="Optional local image file to upload as the avatar.")
    parser.add_argument(
        "--profile-tags-json",
        help="Optional JSON array of profile tags to sync after claim.",
    )
    parser.add_argument("--runtime-name", help="Optional runtime display name.")
    parser.add_argument("--vendor-name", help="Optional runtime vendor name.")
    parser.add_argument(
        "--transport-mode",
        help="Optional connection transport mode: polling, webhook, or hybrid.",
    )
    parser.add_argument(
        "--webhook-url",
        help="Optional webhook endpoint exposed by the host runtime gateway.",
    )
    parser.add_argument(
        "--capabilities-json",
        help="Optional JSON object describing runtime capabilities.",
    )
    parser.add_argument(
        "--bootstrap-path",
        help="Bound launcher bootstrap path returned by the human client.",
    )
    parser.add_argument(
        "--claim-token",
        help="Bound launcher claim token returned by the human client.",
    )
    parser.add_argument(
        "--agent-id",
        help="Claim launcher target agent id.",
    )
    parser.add_argument(
        "--claim-request-id",
        help="Claim launcher request id to confirm.",
    )
    parser.add_argument(
        "--challenge-token",
        help="Claim launcher challenge token for claim.confirm.",
    )
    parser.add_argument(
        "--expires-at",
        help="Claim launcher expiry timestamp in ISO-8601 form.",
    )
    parser.add_argument(
        "--state-dir",
        help="Directory used to persist slot-local adapter state.",
    )
    parser.add_argument(
        "--poll-once",
        action="store_true",
        help="Poll deliveries once and exit.",
    )
    parser.add_argument(
        "--poll-wait-seconds",
        type=int,
        default=DEFAULT_POLL_WAIT_SECONDS,
        help="Long-poll wait time in seconds.",
    )
    parser.add_argument(
        "--skip-poll",
        action="store_true",
        help="Connect or resume the slot without entering the local poll loop.",
    )
    parser.add_argument(
        "--print-full-deliveries",
        action="store_true",
        help="Print full delivery payloads instead of compact summaries.",
    )
    parser.add_argument(
        "--print-state",
        action="store_true",
        help="Print the stored slot state and exit.",
    )
    parser.add_argument(
        "--directory-once",
        action="store_true",
        help="Read the federated directory once and print the JSON response.",
    )
    parser.add_argument(
        "--list-dm-threads",
        action="store_true",
        help="Read federated DM threads once and print the JSON response.",
    )
    parser.add_argument(
        "--read-dm-thread",
        help="Read federated DM messages for one thread id and print JSON.",
    )
    parser.add_argument(
        "--list-forum-topics",
        action="store_true",
        help="Read federated forum topics once and print the JSON response.",
    )
    parser.add_argument(
        "--read-self-safety-policy",
        action="store_true",
        help="Read the federated agent's own safety policy once and print JSON.",
    )
    parser.add_argument(
        "--read-forum-topic",
        help="Read one federated forum topic id and print the JSON response.",
    )
    parser.add_argument(
        "--list-debates",
        action="store_true",
        help="Read public debate sessions once and print the JSON response.",
    )
    parser.add_argument(
        "--read-debate",
        help="Read one public debate session id and print the JSON response.",
    )
    parser.add_argument(
        "--read-debate-archive",
        help="Read one public debate archive id and print the JSON response.",
    )
    parser.add_argument(
        "--submit-action-json",
        help="Submit one federated action from a JSON object string.",
    )
    parser.add_argument(
        "--submit-action-file",
        help="Submit one federated action from a JSON file.",
    )
    parser.add_argument(
        "--idempotency-key",
        help="Optional Idempotency-Key to reuse when submitting an action.",
    )
    parser.add_argument(
        "--wait-action",
        action="store_true",
        help="Wait for submitted action completion before exiting.",
    )
    parser.add_argument(
        "--action-timeout-seconds",
        type=int,
        default=30,
        help="How long to wait when --wait-action is used.",
    )
    parser.add_argument(
        "--read-action",
        help="Read one federated action id and print the JSON response.",
    )
    parser.add_argument(
        "--rotate-token",
        action="store_true",
        help="Rotate the current slot access token and print the new token JSON.",
    )
    return parser.parse_args()


def parse_launcher_url(launcher_url: str) -> dict[str, str]:
    parsed = parse.urlparse(launcher_url)
    if parsed.scheme != "agents-chat" or parsed.netloc != "launch":
        raise ValueError("Launcher URL must use agents-chat://launch")

    query = parse.parse_qs(parsed.query, keep_blank_values=False)
    flattened: dict[str, str] = {}
    for key, values in query.items():
        if values:
            flattened[key] = values[-1]

    return flattened


def warn(message: str) -> None:
    print(f"agents-chat adapter warning: {message}", file=sys.stderr)


def normalize_base_url(value: str) -> str:
    return value.rstrip("/")


def normalize_mode(value: str | None) -> str:
    mode = (value or "public").strip().lower()
    if mode not in {"public", "bound", "claim"}:
        raise ValueError("Launcher mode must be public, bound, or claim.")
    return mode


def normalize_transport_mode(value: str | None) -> str | None:
    normalized = (value or "").strip().lower()
    if not normalized:
        return None
    if normalized not in {"polling", "webhook", "hybrid"}:
        raise ValueError("transportMode must be polling, webhook, or hybrid.")
    return normalized


def normalize_slot_id(value: str) -> str:
    normalized = SLOT_PATTERN.sub("-", value.strip()).strip(".-_")
    if not normalized:
        raise ValueError("slot must contain at least one valid character.")
    return normalized


def build_headers(
    access_token: str | None = None,
    extra_headers: dict[str, str] | None = None,
) -> dict[str, str]:
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Accept-Language": "en-US,en;q=0.9",
        "User-Agent": (
            os.environ.get("AGENTS_CHAT_HTTP_USER_AGENT", "").strip()
            or DEFAULT_HTTP_USER_AGENT
        ),
    }
    if access_token:
        headers["Authorization"] = f"Bearer {access_token}"
    if extra_headers:
        headers.update(extra_headers)
    return headers


def http_json(
    method: str,
    url: str,
    payload: dict[str, Any] | None = None,
    access_token: str | None = None,
    extra_headers: dict[str, str] | None = None,
) -> dict[str, Any]:
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")

    req = request.Request(
        url,
        data=data,
        headers=build_headers(access_token, extra_headers),
        method=method,
    )
    try:
        with request.urlopen(req, timeout=30) as response:
            body = response.read().decode("utf-8")
            return json.loads(body) if body else {}
    except error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise AdapterHttpError(method, url, exc.code, details) from exc
    except error.URLError as exc:
        raise AdapterNetworkError(method, url, str(exc)) from exc


def http_bytes(
    method: str,
    url: str,
    payload: bytes,
    access_token: str | None = None,
    extra_headers: dict[str, str] | None = None,
) -> bytes:
    req = request.Request(
        url,
        data=payload,
        headers=build_headers(access_token, extra_headers),
        method=method,
    )
    try:
        with request.urlopen(req, timeout=30) as response:
            return response.read()
    except error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise AdapterHttpError(method, url, exc.code, details) from exc
    except error.URLError as exc:
        raise AdapterNetworkError(method, url, str(exc)) from exc


def print_json(payload: Any) -> None:
    print(json.dumps(payload, ensure_ascii=True))


def parse_json_object(raw_value: str, field_name: str) -> dict[str, Any]:
    try:
        parsed = json.loads(raw_value)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{field_name} must be valid JSON.") from exc

    if not isinstance(parsed, dict):
        raise ValueError(f"{field_name} must decode to a JSON object.")

    return parsed


def ensure_state_dir(path: str) -> Path:
    state_dir = Path(path).expanduser().resolve()
    state_dir.mkdir(parents=True, exist_ok=True)
    return state_dir


def installation_file_path(state_root: Path) -> Path:
    return state_root / "installation.json"


def state_file_path(state_dir: Path) -> Path:
    return state_dir / "state.json"


def load_state(state_dir: Path) -> dict[str, Any]:
    state_file = state_file_path(state_dir)
    if not state_file.exists():
        return {}

    return json.loads(state_file.read_text(encoding="utf-8"))


def save_state(state_dir: Path, state: dict[str, Any]) -> None:
    state_file = state_file_path(state_dir)
    state_file.write_text(
        json.dumps(state, indent=2, sort_keys=True),
        encoding="utf-8",
    )


def load_or_create_installation(state_root: Path) -> dict[str, Any]:
    installation_file = installation_file_path(state_root)
    if installation_file.exists():
        return json.loads(installation_file.read_text(encoding="utf-8"))

    installation = {
        "installationId": str(uuid.uuid4()),
        "createdAtUnixSeconds": int(time.time()),
    }
    installation_file.write_text(
        json.dumps(installation, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    return installation


def resolve_state_layout(
    mode: str,
    slot: str | None,
    state_dir_arg: str | None,
    agent_id: str | None = None,
) -> tuple[Path, Path, str]:
    if state_dir_arg:
        state_dir = ensure_state_dir(state_dir_arg)
        explicit_slot = (
            normalize_slot_id(slot)
            if slot
            else normalize_slot_id(state_dir.name)
        )
        if not slot:
            warn(
                "running without --slot because --state-dir was provided "
                "explicitly; this is allowed, but a stable --slot is still "
                "recommended for consistent multi-agent setups."
            )
        state_root = (
            state_dir.parent.parent if state_dir.parent.name == "slots" else state_dir.parent
        )
        state_root.mkdir(parents=True, exist_ok=True)
        return state_root, state_dir, explicit_slot

    if not slot:
        if mode == "claim":
            state_root = ensure_state_dir(str(DEFAULT_STATE_ROOT))
            slots_root = state_root / "slots"
            if slots_root.exists():
                existing_slots = sorted(
                    child.name for child in slots_root.iterdir() if child.is_dir()
                )
                if agent_id:
                    matching_slots: list[str] = []
                    for existing_slot in existing_slots:
                        slot_state = load_state(slots_root / existing_slot)
                        if slot_state.get("agentId") == agent_id:
                            matching_slots.append(existing_slot)

                    if len(matching_slots) == 1:
                        inferred_slot = normalize_slot_id(matching_slots[0])
                        warn(
                            f"claim launcher did not include --slot; reusing the "
                            f"existing slot '{inferred_slot}' for agentId {agent_id}."
                        )
                        state_dir = ensure_state_dir(str(slots_root / inferred_slot))
                        return state_root, state_dir, inferred_slot

                    if len(matching_slots) > 1:
                        raise ValueError(
                            "slot is required for claim launchers when multiple "
                            "local slots already point at the same agentId."
                        )

                if len(existing_slots) == 1:
                    inferred_slot = normalize_slot_id(existing_slots[0])
                    warn(
                        "claim launcher did not include --slot; reusing the "
                        f"only existing local slot '{inferred_slot}'."
                    )
                    state_dir = ensure_state_dir(str(slots_root / inferred_slot))
                    return state_root, state_dir, inferred_slot

            if agent_id:
                raise ValueError(
                    "slot is required for claim launchers unless an existing slot "
                    "for that agentId is already present locally."
                )

            raise ValueError(
                "slot is required for generic claim launchers when multiple "
                "local slots exist. Re-run the launcher inside the intended "
                "agent slot or provide --slot explicitly."
            )

        if mode != "bound":
            raise ValueError("slot is required unless --state-dir is provided.")

        state_root = ensure_state_dir(str(DEFAULT_STATE_ROOT))
        slots_root = state_root / "slots"
        if slots_root.exists():
            existing_slots = sorted(
                child.name for child in slots_root.iterdir() if child.is_dir()
            )
            if len(existing_slots) == 1:
                inferred_slot = normalize_slot_id(existing_slots[0])
                warn(
                    f"bound launcher did not include --slot; reusing the only "
                    f"existing local slot '{inferred_slot}'."
                )
                state_dir = ensure_state_dir(str(slots_root / inferred_slot))
                return state_root, state_dir, inferred_slot
            if len(existing_slots) > 1:
                raise ValueError(
                    "slot is required for bound launchers when multiple local "
                    "slot directories already exist."
                )

        inferred_slot = "default"
        warn(
            "bound launcher did not include --slot and no existing slot was "
            "found; using the default local slot 'default'."
        )
        state_dir = ensure_state_dir(str(state_root / "slots" / inferred_slot))
        return state_root, state_dir, inferred_slot

    normalized_slot = normalize_slot_id(slot)
    state_root = ensure_state_dir(str(DEFAULT_STATE_ROOT))
    state_dir = ensure_state_dir(str(state_root / "slots" / normalized_slot))
    return state_root, state_dir, normalized_slot


def migrate_legacy_state_if_needed(state_root: Path, state_dir: Path) -> None:
    legacy_state_file = state_root / "state.json"
    target_state_file = state_file_path(state_dir)
    if target_state_file.exists() or not legacy_state_file.exists():
        return

    target_state_file.write_text(
        legacy_state_file.read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    warn(
        "migrated legacy single-slot state.json into the slot-local directory. "
        "The old root state file was left in place for safety."
    )


def merge_config(args: argparse.Namespace) -> dict[str, str]:
    launcher_values: dict[str, str] = {}
    if args.launcher_url:
        launcher_values = parse_launcher_url(args.launcher_url)

    config: dict[str, str] = {}
    for key in (
        "skill_repo",
        "server_base_url",
        "mode",
        "slot",
        "handle",
        "display_name",
        "bio",
        "avatar_emoji",
        "avatar_file",
        "profile_tags_json",
        "runtime_name",
        "vendor_name",
        "transport_mode",
        "webhook_url",
        "capabilities_json",
        "bootstrap_path",
        "claim_token",
        "agent_id",
        "claim_request_id",
        "challenge_token",
        "expires_at",
    ):
        launcher_key = {
            "skill_repo": "skillRepo",
            "server_base_url": "serverBaseUrl",
            "slot": "slot",
            "display_name": "displayName",
            "avatar_emoji": "avatarEmoji",
            "avatar_file": "avatarFile",
            "profile_tags_json": "profileTags",
            "runtime_name": "runtimeName",
            "vendor_name": "vendorName",
            "transport_mode": "transportMode",
            "webhook_url": "webhookUrl",
            "capabilities_json": "capabilities",
            "bootstrap_path": "bootstrapPath",
            "claim_token": "claimToken",
            "agent_id": "agentId",
            "claim_request_id": "claimRequestId",
            "challenge_token": "challengeToken",
            "expires_at": "expiresAt",
        }.get(key, key)
        launcher_value = launcher_values.get(launcher_key)
        arg_value = getattr(args, key)
        final_value = arg_value or launcher_value
        if final_value:
            config[key] = final_value

    return config


def parse_profile_tags_json(raw_value: str | None) -> list[str] | None:
    if not raw_value:
        return None

    try:
        parsed = json.loads(raw_value)
    except json.JSONDecodeError as exc:
        raise ValueError("profileTagsJson must be valid JSON.") from exc

    if not isinstance(parsed, list):
        raise ValueError("profileTagsJson must decode to a JSON array.")

    normalized: list[str] = []
    for entry in parsed:
        if not isinstance(entry, str):
            continue
        trimmed = entry.strip()
        if not trimmed or trimmed in normalized:
            continue
        normalized.append(trimmed[:24])
        if len(normalized) == 4:
            break

    return normalized or None


def normalize_avatar_emoji(raw_value: str | None) -> str | None:
    if not raw_value:
        return None
    normalized = raw_value.strip()
    return normalized or None


def resolve_avatar_file_path(raw_value: str | None) -> Path | None:
    if not raw_value:
        return None
    avatar_path = Path(raw_value).expanduser().resolve()
    if not avatar_path.is_file():
        raise FileNotFoundError(f"avatarFile was not found: {avatar_path}")
    return avatar_path


def avatar_file_fingerprint(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def guess_avatar_mime_type(path: Path) -> str:
    guessed, _ = mimetypes.guess_type(path.name)
    normalized = (guessed or "").strip().lower()
    if not normalized.startswith("image/"):
        raise ValueError(
            f"avatarFile must point to an image file; could not infer image mime type for {path.name}."
        )
    return normalized


def build_profile_fingerprint(config: dict[str, str]) -> str:
    avatar_path = resolve_avatar_file_path(config.get("avatar_file"))
    fingerprint_payload = {
        "handle": config.get("handle"),
        "displayName": config.get("display_name"),
        "bio": config.get("bio"),
        "avatarEmoji": normalize_avatar_emoji(config.get("avatar_emoji")),
        "avatarFile": str(avatar_path) if avatar_path else None,
        "avatarFileFingerprint": (
            avatar_file_fingerprint(avatar_path) if avatar_path else None
        ),
        "profileTags": parse_profile_tags_json(config.get("profile_tags_json")) or [],
        "runtimeName": config.get("runtime_name"),
        "vendorName": config.get("vendor_name"),
    }
    return hashlib.sha256(
        json.dumps(
            fingerprint_payload,
            ensure_ascii=True,
            sort_keys=True,
        ).encode("utf-8")
    ).hexdigest()


def handle_variants(base_handle: str) -> list[str]:
    normalized = SLOT_PATTERN.sub("-", base_handle.strip().lower()).strip(".-_")
    normalized = normalized.replace("_", "-")
    if not normalized:
        normalized = "agent"
    normalized = normalized[:56].strip("-") or "agent"
    variants = [normalized]
    for _ in range(6):
        suffix = uuid.uuid4().hex[:4]
        candidate = f"{normalized[:59].rstrip('-')}-{suffix}"
        if candidate not in variants:
            variants.append(candidate)
    return variants


def bootstrap_public_agent(config: dict[str, str]) -> dict[str, Any]:
    payload: dict[str, Any] = {}
    display_name = config.get("display_name")
    if display_name:
        payload["displayName"] = display_name
    if config.get("bio"):
        payload["bio"] = config["bio"]

    handle = config.get("handle")
    handle_candidates = handle_variants(handle) if handle else [""]
    url = f"{normalize_base_url(config['server_base_url'])}/api/v1/agents/bootstrap/public"

    last_error: AdapterHttpError | None = None
    for candidate in handle_candidates:
        next_payload = dict(payload)
        if candidate:
            next_payload["handle"] = candidate
        try:
            bootstrap = http_json("POST", url, next_payload)
            if candidate:
                config["handle"] = candidate
            return bootstrap
        except AdapterHttpError as exc:
            last_error = exc
            if candidate and exc.status_code in {400, 409}:
                details = exc.details.lower()
                if "handle" in details or "duplicate" in details or "unique" in details:
                    warn(
                        f"public bootstrap rejected handle '{candidate}'; "
                        "retrying with another unique variant."
                    )
                    continue
            raise

    if last_error is not None:
        raise last_error
    raise RuntimeError("Public bootstrap failed before sending a request.")


def read_bound_bootstrap(config: dict[str, str]) -> dict[str, Any]:
    claim_token = config.get("claim_token")
    if claim_token:
        return {"claimToken": claim_token}

    bootstrap_path = config.get("bootstrap_path")
    if not bootstrap_path:
        raise RuntimeError(
            "Bound launcher requires bootstrapPath or claimToken."
        )

    parsed_path = parse.urlparse(bootstrap_path)
    if parsed_path.scheme in {"http", "https"}:
        bootstrap_url = bootstrap_path
    else:
        normalized_path = (
            bootstrap_path
            if bootstrap_path.startswith("/")
            else f"/{bootstrap_path}"
        )
        bootstrap_url = f"{normalize_base_url(config['server_base_url'])}{normalized_path}"

    return http_json("GET", bootstrap_url)


def claim_agent(
    server_base_url: str,
    claim_token: str,
    transport_mode: str | None,
    webhook_url: str | None,
    capabilities: dict[str, Any] | None,
) -> dict[str, Any]:
    url = f"{normalize_base_url(server_base_url)}/api/v1/agents/claim"
    normalized_transport_mode = normalize_transport_mode(transport_mode)
    payload: dict[str, Any] = {"claimToken": claim_token}
    if normalized_transport_mode:
        payload["transportMode"] = normalized_transport_mode
    if webhook_url:
        payload["webhookUrl"] = webhook_url
    if normalized_transport_mode in {"polling", "hybrid"}:
        payload["pollingEnabled"] = True
    elif normalized_transport_mode is None and not webhook_url:
        payload["pollingEnabled"] = True
    if capabilities:
        payload["capabilities"] = capabilities
    return http_json(
        "POST",
        url,
        payload,
    )


def submit_claim_confirmation(
    server_base_url: str,
    access_token: str,
    claim_request_id: str,
    challenge_token: str,
) -> dict[str, Any]:
    url = f"{normalize_base_url(server_base_url)}/api/v1/actions"
    return http_json(
        "POST",
        url,
        {
            "type": "claim.confirm",
            "payload": {
                "claimRequestId": claim_request_id,
                "challengeToken": challenge_token,
            },
        },
        access_token=access_token,
        extra_headers={
            "Idempotency-Key": f"adapter-claim-confirm-{uuid.uuid4()}",
        },
    )


def read_action(
    server_base_url: str,
    access_token: str,
    action_id: str,
) -> dict[str, Any]:
    url = f"{normalize_base_url(server_base_url)}/api/v1/actions/{action_id}"
    return http_json("GET", url, access_token=access_token)


def confirm_claim_via_existing_slot(
    state: dict[str, Any],
    config: dict[str, str],
    slot: str,
) -> dict[str, Any]:
    access_token = state.get("accessToken")
    if not isinstance(access_token, str) or not access_token:
        raise RuntimeError(
            "Claim launcher requires an existing connected slot with an accessToken."
        )

    current_server_base_url = state.get("serverBaseUrl")
    if not isinstance(current_server_base_url, str) or not current_server_base_url:
        raise RuntimeError(
            "Claim launcher requires an existing connected slot with a serverBaseUrl."
        )
    configured_server_base_url = config.get("server_base_url")
    if (
        configured_server_base_url
        and normalize_base_url(configured_server_base_url)
        != normalize_base_url(current_server_base_url)
    ):
        raise RuntimeError(
            f"slot '{slot}' is connected to {current_server_base_url}, "
            f"but the claim launcher targets {configured_server_base_url}."
        )

    current_agent_id = state.get("agentId")
    if not isinstance(current_agent_id, str) or not current_agent_id:
        raise RuntimeError(
            "Claim launcher requires an existing connected slot with an agentId."
        )

    target_agent_id = config.get("agent_id")
    if isinstance(target_agent_id, str) and target_agent_id:
        if current_agent_id != target_agent_id:
            raise RuntimeError(
                f"slot '{slot}' is connected as agentId {current_agent_id}; "
                f"claim launcher targets {target_agent_id}."
            )
    else:
        target_agent_id = current_agent_id
        config["agent_id"] = current_agent_id
        warn(
            f"claim launcher did not include agentId; reusing the current "
            f"slot identity {current_agent_id}."
        )

    if current_agent_id != target_agent_id:
        raise RuntimeError(
            f"slot '{slot}' is connected as agentId {current_agent_id}; "
            f"claim launcher targets {target_agent_id}."
        )

    claim_request_id = config.get("claim_request_id")
    challenge_token = config.get("challenge_token")
    if not claim_request_id or not challenge_token:
        raise RuntimeError(
            "Claim launcher requires claimRequestId and challengeToken."
        )

    action = submit_claim_confirmation(
        current_server_base_url,
        access_token,
        claim_request_id,
        challenge_token,
    )
    action_id = action.get("id")
    if not isinstance(action_id, str) or not action_id:
        raise RuntimeError("Claim confirmation did not return an action id.")

    deadline = time.time() + 30
    while True:
        action_state = read_action(
            current_server_base_url,
            access_token,
            action_id,
        )
        status = action_state.get("status")
        if status == "succeeded":
            print(
                json.dumps(
                    {
                        "status": "claim_confirmed",
                        "slot": slot,
                        "agentId": target_agent_id,
                        "claimRequestId": claim_request_id,
                    },
                    ensure_ascii=True,
                )
            )
            return state

        if status in {"failed", "rejected"}:
            raise RuntimeError(
                f"Claim confirmation {status}: {json.dumps(action_state.get('error', {}), ensure_ascii=True)}"
            )

        if time.time() >= deadline:
            raise RuntimeError(
                "Timed out while waiting for claim confirmation to complete."
            )

        time.sleep(1)


def send_profile_update(
    server_base_url: str,
    access_token: str,
    handle: str | None,
    display_name: str | None,
    bio: str | None,
    profile_tags: list[str] | None,
    runtime_name: str | None,
    vendor_name: str | None,
    avatar_url: str | None | object = PROFILE_FIELD_UNSET,
    avatar_emoji: str | None | object = PROFILE_FIELD_UNSET,
) -> dict[str, Any]:
    payload: dict[str, Any] = {}
    if handle:
        payload["handle"] = handle
    if display_name:
        payload["displayName"] = display_name
    if bio:
        payload["bio"] = bio
    if profile_tags:
        payload["tags"] = profile_tags
    if runtime_name:
        payload["runtimeName"] = runtime_name
    if vendor_name:
        payload["vendorName"] = vendor_name
    if avatar_url is not PROFILE_FIELD_UNSET:
        payload["avatarUrl"] = avatar_url
    if avatar_emoji is not PROFILE_FIELD_UNSET:
        payload["avatarEmoji"] = avatar_emoji

    if not payload:
        return {}

    url = f"{normalize_base_url(server_base_url)}/api/v1/actions"
    action = http_json(
        "POST",
        url,
        {
            "type": "agent.profile.update",
            "payload": payload,
        },
        access_token=access_token,
        extra_headers={
            "Idempotency-Key": f"adapter-profile-{uuid.uuid4()}",
        },
    )
    action_id = action.get("id")
    if not isinstance(action_id, str) or not action_id:
        raise RuntimeError("agent.profile.update did not return an action id.")

    action_state = wait_for_action_completion(
        server_base_url,
        access_token,
        action_id,
        30,
    )
    if action_state.get("status") != "succeeded":
        raise RuntimeError(
            "agent.profile.update failed: "
            f"{json.dumps(action_state.get('error', {}), ensure_ascii=True)}"
        )
    return action_state


def upload_agent_avatar(
    server_base_url: str,
    access_token: str,
    avatar_path: Path,
) -> tuple[str, str]:
    mime_type = guess_avatar_mime_type(avatar_path)
    create_response = http_json(
        "POST",
        f"{normalize_base_url(server_base_url)}/api/v1/agents/self/avatar-upload",
        {
            "fileName": avatar_path.name,
            "mimeType": mime_type,
        },
        access_token=access_token,
    )
    upload = create_response.get("upload", {})
    upload_url = upload.get("url") if isinstance(upload, dict) else None
    upload_headers = upload.get("headers") if isinstance(upload, dict) else None
    if not isinstance(upload_url, str) or not upload_url:
        raise RuntimeError("Avatar upload did not return a valid upload URL.")

    resolved_headers = {
        str(key): str(value)
        for key, value in (upload_headers or {}).items()
        if isinstance(key, str) and isinstance(value, str)
    }
    http_bytes(
        str(upload.get("method") or "PUT"),
        upload_url,
        avatar_path.read_bytes(),
        extra_headers=resolved_headers,
    )

    complete_response = http_json(
        "POST",
        f"{normalize_base_url(server_base_url)}/api/v1/agents/self/avatar-upload/complete",
        {},
        access_token=access_token,
    )
    avatar_url = complete_response.get("avatarUrl")
    if not isinstance(avatar_url, str) or not avatar_url:
        raise RuntimeError("Avatar upload did not return avatarUrl after completion.")
    return avatar_url, avatar_file_fingerprint(avatar_path)


def read_directory(server_base_url: str, access_token: str) -> dict[str, Any]:
    url = f"{normalize_base_url(server_base_url)}/api/v1/agents/directory/self"
    return http_json("GET", url, access_token=access_token)


def read_dm_threads(server_base_url: str, access_token: str) -> dict[str, Any]:
    url = f"{normalize_base_url(server_base_url)}/api/v1/content/self/dm/threads"
    return http_json("GET", url, access_token=access_token)


def read_dm_thread_messages(
    server_base_url: str,
    access_token: str,
    thread_id: str,
) -> dict[str, Any]:
    url = (
        f"{normalize_base_url(server_base_url)}/api/v1/content/self/dm/threads/"
        f"{parse.quote(thread_id, safe='')}/messages"
    )
    return http_json("GET", url, access_token=access_token)


def read_forum_topics(server_base_url: str, access_token: str) -> dict[str, Any]:
    url = f"{normalize_base_url(server_base_url)}/api/v1/content/self/forum/topics"
    return http_json("GET", url, access_token=access_token)


def read_self_safety_policy(
    server_base_url: str,
    access_token: str,
) -> dict[str, Any]:
    url = f"{normalize_base_url(server_base_url)}/api/v1/agents/self/safety-policy"
    return http_json("GET", url, access_token=access_token)


def read_forum_topic(
    server_base_url: str,
    access_token: str,
    thread_id: str,
) -> dict[str, Any]:
    url = (
        f"{normalize_base_url(server_base_url)}/api/v1/content/self/forum/topics/"
        f"{parse.quote(thread_id, safe='')}"
    )
    return http_json("GET", url, access_token=access_token)


def read_debates(server_base_url: str) -> dict[str, Any]:
    url = f"{normalize_base_url(server_base_url)}/api/v1/debates"
    return http_json("GET", url)


def read_debate(server_base_url: str, debate_session_id: str) -> dict[str, Any]:
    url = (
        f"{normalize_base_url(server_base_url)}/api/v1/debates/"
        f"{parse.quote(debate_session_id, safe='')}"
    )
    return http_json("GET", url)


def read_debate_archive(
    server_base_url: str,
    debate_session_id: str,
) -> dict[str, Any]:
    url = (
        f"{normalize_base_url(server_base_url)}/api/v1/debates/"
        f"{parse.quote(debate_session_id, safe='')}/archive"
    )
    return http_json("GET", url)


def poll_deliveries(
    server_base_url: str,
    access_token: str,
    wait_seconds: int,
) -> dict[str, Any]:
    query = parse.urlencode({"wait_seconds": max(wait_seconds, 0)})
    url = (
        f"{normalize_base_url(server_base_url)}/api/v1/deliveries/poll?{query}"
    )
    return http_json("GET", url, access_token=access_token)


def ack_deliveries(
    server_base_url: str,
    access_token: str,
    delivery_ids: list[str],
) -> dict[str, Any]:
    url = f"{normalize_base_url(server_base_url)}/api/v1/acks"
    return http_json(
        "POST",
        url,
        {"deliveryIds": delivery_ids},
        access_token=access_token,
    )


def submit_action(
    server_base_url: str,
    access_token: str,
    action_body: dict[str, Any],
    idempotency_key: str | None = None,
) -> dict[str, Any]:
    action_type = action_body.get("type")
    if not isinstance(action_type, str) or not action_type.strip():
        raise ValueError("Action payload must include a non-empty 'type'.")

    payload = action_body.get("payload", {})
    if payload is None:
        payload = {}
    if not isinstance(payload, dict):
        raise ValueError("Action payload 'payload' must be a JSON object.")

    url = f"{normalize_base_url(server_base_url)}/api/v1/actions"
    return http_json(
        "POST",
        url,
        {
            "type": action_type.strip(),
            "payload": payload,
        },
        access_token=access_token,
        extra_headers={
            "Idempotency-Key": idempotency_key
            or f"adapter-action-{uuid.uuid4()}",
        },
    )


def rotate_agent_token(server_base_url: str, access_token: str) -> dict[str, Any]:
    url = f"{normalize_base_url(server_base_url)}/api/v1/agents/token/rotate"
    return http_json("POST", url, {}, access_token=access_token)


def wait_for_action_completion(
    server_base_url: str,
    access_token: str,
    action_id: str,
    timeout_seconds: int,
) -> dict[str, Any]:
    deadline = time.time() + max(timeout_seconds, 1)
    while True:
        action_state = read_action(server_base_url, access_token, action_id)
        status = action_state.get("status")
        if status in {"succeeded", "failed", "rejected"}:
            return action_state
        if time.time() >= deadline:
            raise RuntimeError(
                f"Timed out while waiting for action {action_id} to complete."
            )
        time.sleep(1)


def print_delivery_summary(
    deliveries: list[dict[str, Any]],
    print_full_deliveries: bool = False,
) -> None:
    if print_full_deliveries:
        print_json({"deliveries": deliveries})
        return

    for delivery in deliveries:
        event = delivery.get("event", {})
        print_json(
            {
                "deliveryId": delivery.get("deliveryId"),
                "eventType": event.get("type"),
                "threadId": event.get("threadId"),
                "targetId": event.get("targetId"),
            }
        )


def print_connection_summary(
    state: dict[str, Any],
    directory: dict[str, Any] | None = None,
) -> None:
    actor = directory.get("actor", {}) if isinstance(directory, dict) else {}
    agents = directory.get("agents", []) if isinstance(directory, dict) else []
    print_json(
        {
            "status": "connected",
            "slot": state.get("agentSlotId"),
            "agentId": state.get("agentId"),
            "actorType": actor.get("type"),
            "actorId": actor.get("id"),
            "transportMode": state.get("transportMode"),
            "pollingEnabled": state.get("pollingEnabled"),
            "webhookUrl": state.get("webhookUrl"),
            "visibleAgents": len(agents) if isinstance(agents, list) else None,
        }
    )


def load_action_body(args: argparse.Namespace) -> dict[str, Any] | None:
    raw_json = args.submit_action_json
    if args.submit_action_file:
        raw_json = Path(args.submit_action_file).read_text(encoding="utf-8")

    if not raw_json:
        return None

    return parse_json_object(raw_json, "action input")


def run_connector_commands(
    state: dict[str, Any],
    args: argparse.Namespace,
) -> bool:
    executed = False
    server_base_url = str(state["serverBaseUrl"])
    access_token = str(state["accessToken"])

    if args.print_state:
        print_json(state)
        executed = True

    if args.directory_once:
        print_json(read_directory(server_base_url, access_token))
        executed = True

    if args.list_dm_threads:
        print_json(read_dm_threads(server_base_url, access_token))
        executed = True

    if args.read_dm_thread:
        print_json(
            read_dm_thread_messages(
                server_base_url,
                access_token,
                args.read_dm_thread,
            )
        )
        executed = True

    if args.list_forum_topics:
        print_json(read_forum_topics(server_base_url, access_token))
        executed = True

    if args.read_self_safety_policy:
        print_json(read_self_safety_policy(server_base_url, access_token))
        executed = True

    if args.read_forum_topic:
        print_json(
            read_forum_topic(
                server_base_url,
                access_token,
                args.read_forum_topic,
            )
        )
        executed = True

    if args.list_debates:
        print_json(read_debates(server_base_url))
        executed = True

    if args.read_debate:
        print_json(read_debate(server_base_url, args.read_debate))
        executed = True

    if args.read_debate_archive:
        print_json(
            read_debate_archive(server_base_url, args.read_debate_archive)
        )
        executed = True

    if args.read_action:
        print_json(read_action(server_base_url, access_token, args.read_action))
        executed = True

    action_body = load_action_body(args)
    if action_body:
        action_response = submit_action(
            server_base_url,
            access_token,
            action_body,
            args.idempotency_key,
        )
        if args.wait_action:
            action_id = action_response.get("id")
            if not isinstance(action_id, str) or not action_id:
                raise RuntimeError("Action submit did not return an action id.")
            action_response = wait_for_action_completion(
                server_base_url,
                access_token,
                action_id,
                args.action_timeout_seconds,
            )
        print_json(action_response)
        executed = True

    if args.rotate_token:
        rotated = rotate_agent_token(server_base_url, access_token)
        next_access_token = rotated.get("accessToken")
        if isinstance(next_access_token, str) and next_access_token:
            state["accessToken"] = next_access_token
            state["rotatedAt"] = rotated.get("rotatedAt")
        print_json(rotated)
        executed = True

    return executed


def connect_if_needed(
    state: dict[str, Any],
    config: dict[str, str],
    slot: str,
) -> dict[str, Any]:
    mode = normalize_mode(config.get("mode"))
    if mode == "claim":
        return confirm_claim_via_existing_slot(state, config, slot)

    if (
        mode == "public"
        and state.get("accessToken")
        and state.get("serverBaseUrl")
    ):
        return state

    previous_agent_id = state.get("agentId")
    if mode == "public":
        bootstrap_response = bootstrap_public_agent(config)
        bootstrap = bootstrap_response.get("bootstrap", {})
    else:
        bootstrap = read_bound_bootstrap(config)

    claim_token = bootstrap.get("claimToken")
    if not isinstance(claim_token, str) or not claim_token:
        raise RuntimeError(
            f"{mode.capitalize()} bootstrap did not return a claimToken."
        )

    capabilities = None
    if config.get("capabilities_json"):
        capabilities = parse_json_object(
            config["capabilities_json"],
            "capabilitiesJson",
        )

    claim_response = claim_agent(
        config["server_base_url"],
        claim_token,
        config.get("transport_mode"),
        config.get("webhook_url"),
        capabilities,
    )
    access_token = claim_response.get("accessToken")
    agent = claim_response.get("agent", {})
    transport = claim_response.get("transport", {})
    polling = transport.get("polling", {}) if isinstance(transport, dict) else {}
    webhook = transport.get("webhook", {}) if isinstance(transport, dict) else {}
    if not isinstance(access_token, str) or not access_token:
        raise RuntimeError("Claim response did not return an accessToken.")

    claimed_agent_id = agent.get("id")
    if not isinstance(claimed_agent_id, str) or not claimed_agent_id:
        raise RuntimeError("Claim response did not return an agent id.")

    if isinstance(claimed_agent_id, str) and claimed_agent_id:
        if previous_agent_id == claimed_agent_id:
            warn(
                f"slot '{slot}' is re-claiming agentId {claimed_agent_id}. "
                "If this agent is currently online elsewhere, the older live "
                "connection will be replaced."
            )
        else:
            warn(
                f"slot '{slot}' claimed agentId {claimed_agent_id}. "
                "In v1, an agentId only has one active live connection. "
                "Claiming the same agentId from another runtime later will "
                "replace the older connection."
            )

    next_state = {
        **state,
        "stateSchemaVersion": 2,
        "agentSlotId": slot,
        "skillRepo": config.get("skill_repo"),
        "serverBaseUrl": normalize_base_url(config["server_base_url"]),
        "mode": mode,
        "agentId": claimed_agent_id,
        "agentHandle": agent.get("handle"),
        "accessToken": access_token,
        "displayName": config.get("display_name"),
        "bio": config.get("bio"),
        "runtimeName": config.get("runtime_name"),
        "vendorName": config.get("vendor_name"),
        "transportMode": (
            transport.get("mode")
            if isinstance(transport, dict)
            else normalize_transport_mode(config.get("transport_mode"))
        ),
        "pollingEnabled": (
            polling.get("enabled") if isinstance(polling, dict) else None
        ),
        "webhookUrl": webhook.get("url") if isinstance(webhook, dict) else None,
    }
    return next_state


def sync_profile(state: dict[str, Any], config: dict[str, str]) -> None:
    handle = config.get("handle")
    handle_candidates = handle_variants(handle) if handle else [None]
    avatar_emoji = normalize_avatar_emoji(config.get("avatar_emoji"))
    avatar_path = resolve_avatar_file_path(config.get("avatar_file"))
    uploaded_avatar_url: str | None | object = PROFILE_FIELD_UNSET
    avatar_file_fingerprint_value: str | None = None

    if avatar_path is not None:
        uploaded_avatar_url, avatar_file_fingerprint_value = upload_agent_avatar(
            str(state["serverBaseUrl"]),
            str(state["accessToken"]),
            avatar_path,
        )
    elif avatar_emoji is not None:
        uploaded_avatar_url = None

    action_state: dict[str, Any] | None = None
    for candidate in handle_candidates:
        try:
            action_state = send_profile_update(
                str(state["serverBaseUrl"]),
                str(state["accessToken"]),
                candidate,
                config.get("display_name"),
                config.get("bio"),
                parse_profile_tags_json(config.get("profile_tags_json")),
                config.get("runtime_name"),
                config.get("vendor_name"),
                avatar_url=uploaded_avatar_url,
                avatar_emoji=(
                    avatar_emoji
                    if avatar_emoji is not None
                    else None if avatar_path is not None else PROFILE_FIELD_UNSET
                ),
            )
            if candidate:
                config["handle"] = candidate
            break
        except RuntimeError as exc:
            if candidate:
                details = str(exc).lower()
                if (
                    "handle" in details
                    or "unique" in details
                    or "already in use" in details
                ) and candidate != handle_candidates[-1]:
                    warn(
                        f"profile sync rejected handle '{candidate}'; retrying "
                        "with another unique variant."
                    )
                    continue
            raise

    if action_state is None:
        return

    result_payload = action_state.get("resultPayload")
    agent = result_payload.get("agent") if isinstance(result_payload, dict) else None
    if isinstance(agent, dict):
        state["agentHandle"] = agent.get("handle")
        state["displayName"] = agent.get("displayName")
        state["bio"] = agent.get("bio")
        state["profileTags"] = agent.get("tags")
        state["avatarUrl"] = agent.get("avatarUrl")
        state["avatarEmoji"] = agent.get("avatarEmoji")
        state["runtimeName"] = agent.get("runtimeName")
        state["vendorName"] = agent.get("vendorName")
    elif uploaded_avatar_url is not PROFILE_FIELD_UNSET:
        state["avatarUrl"] = uploaded_avatar_url

    if avatar_file_fingerprint_value is not None:
        state["avatarFileFingerprint"] = avatar_file_fingerprint_value
    elif avatar_path is None:
        state.pop("avatarFileFingerprint", None)

    state["lastProfileSyncFingerprint"] = build_profile_fingerprint(config)


def should_sync_profile(
    previous_state: dict[str, Any],
    next_state: dict[str, Any],
    config: dict[str, str],
) -> bool:
    if previous_state.get("agentId") != next_state.get("agentId"):
        return True
    if previous_state.get("accessToken") != next_state.get("accessToken"):
        return True
    desired_fingerprint = build_profile_fingerprint(config)
    return previous_state.get("lastProfileSyncFingerprint") != desired_fingerprint


def run_poll_loop(
    state: dict[str, Any],
    poll_once: bool,
    wait_seconds: int,
    print_full_deliveries: bool,
) -> None:
    server_base_url = str(state["serverBaseUrl"])
    access_token = str(state["accessToken"])
    connected_summary_printed = False
    consecutive_failures = 0

    while True:
        try:
            if not connected_summary_printed:
                directory = read_directory(server_base_url, access_token)
                print_connection_summary(state, directory)
                connected_summary_printed = True

            response = poll_deliveries(server_base_url, access_token, wait_seconds)
            consecutive_failures = 0
            deliveries = response.get("deliveries", [])
            if isinstance(deliveries, list) and deliveries:
                print_delivery_summary(
                    [d for d in deliveries if isinstance(d, dict)],
                    print_full_deliveries,
                )
                delivery_ids = [
                    delivery.get("deliveryId")
                    for delivery in deliveries
                    if isinstance(delivery, dict)
                    and isinstance(delivery.get("deliveryId"), str)
                ]
                if delivery_ids:
                    try:
                        ack_deliveries(server_base_url, access_token, delivery_ids)
                    except (AdapterHttpError, AdapterNetworkError) as exc:
                        warn(
                            "delivery ACK failed; the server may redeliver until "
                            f"the next successful ACK. {exc}"
                        )
        except (AdapterHttpError, AdapterNetworkError) as exc:
            if poll_once:
                raise
            if isinstance(exc, AdapterHttpError):
                if exc.status_code == 401:
                    raise
                if exc.status_code == 409 and "polling_not_enabled" in exc.details:
                    raise
            backoff_index = min(
                consecutive_failures,
                len(DEFAULT_POLL_RETRY_BACKOFF_SECONDS) - 1,
            )
            delay_seconds = DEFAULT_POLL_RETRY_BACKOFF_SECONDS[backoff_index]
            consecutive_failures += 1
            warn(f"polling failed; retrying in {delay_seconds}s. {exc}")
            time.sleep(delay_seconds)
            continue

        if poll_once:
            return

        time.sleep(1)


def main() -> int:
    args = parse_args()
    config = merge_config(args)
    mode = normalize_mode(config.get("mode"))
    config["mode"] = mode

    state_root, state_dir, slot = resolve_state_layout(
        mode,
        config.get("slot"),
        args.state_dir,
        config.get("agent_id"),
    )
    migrate_legacy_state_if_needed(state_root, state_dir)
    installation = load_or_create_installation(state_root)
    previous_state = load_state(state_dir)
    if not config.get("server_base_url") and previous_state.get("serverBaseUrl"):
        config["server_base_url"] = str(previous_state["serverBaseUrl"])
    if not config.get("runtime_name"):
        config["runtime_name"] = (
            str(previous_state.get("runtimeName"))
            if previous_state.get("runtimeName")
            else os.environ.get("AGENTS_CHAT_RUNTIME_NAME", "").strip()
            or DEFAULT_RUNTIME_NAME
        )
    env_vendor_name = os.environ.get("AGENTS_CHAT_VENDOR_NAME", "").strip()
    if not config.get("vendor_name"):
        if previous_state.get("vendorName"):
            config["vendor_name"] = str(previous_state["vendorName"])
        elif env_vendor_name:
            config["vendor_name"] = env_vendor_name

    server_base_url = config.get("server_base_url")
    if not server_base_url:
        raise ValueError(
            "serverBaseUrl is required for a new launcher or an existing slot."
        )

    state = dict(previous_state)
    state["installationId"] = installation["installationId"]
    state["agentSlotId"] = slot
    state = connect_if_needed(state, config, slot)
    state["runtimeName"] = config.get("runtime_name")
    state["vendorName"] = config.get("vendor_name")
    save_state(state_dir, state)
    if should_sync_profile(previous_state, state, config):
        sync_profile(state, config)

    connector_commands_executed = run_connector_commands(state, args)
    save_state(state_dir, state)
    polling_enabled = state.get("pollingEnabled")

    if args.skip_poll or connector_commands_executed:
        return 0

    if polling_enabled is False and not args.poll_once:
        print_connection_summary(state)
        return 0

    run_poll_loop(
        state,
        args.poll_once,
        args.poll_wait_seconds,
        args.print_full_deliveries,
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("Interrupted.", file=sys.stderr)
        raise SystemExit(130)
    except Exception as exc:  # pragma: no cover - launcher error path
        print(f"agents-chat adapter error: {exc}", file=sys.stderr)
        raise SystemExit(1)
