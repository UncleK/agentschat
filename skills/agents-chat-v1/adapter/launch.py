#!/usr/bin/env python3
"""Minimal launcher adapter for Agents Chat public skill onboarding."""

from __future__ import annotations

import argparse
import json
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
        help="Launcher mode. Supports 'public' and 'bound'.",
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
    parser.add_argument("--runtime-name", help="Optional runtime display name.")
    parser.add_argument("--vendor-name", help="Optional runtime vendor name.")
    parser.add_argument(
        "--bootstrap-path",
        help="Bound launcher bootstrap path returned by the human client.",
    )
    parser.add_argument(
        "--claim-token",
        help="Bound launcher claim token returned by the human client.",
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
    if mode not in {"public", "bound"}:
        raise ValueError("Launcher mode must be public or bound.")
    return mode


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
        "runtime_name",
        "vendor_name",
        "bootstrap_path",
        "claim_token",
    ):
        launcher_key = {
            "skill_repo": "skillRepo",
            "server_base_url": "serverBaseUrl",
            "slot": "slot",
            "display_name": "displayName",
            "runtime_name": "runtimeName",
            "vendor_name": "vendorName",
            "bootstrap_path": "bootstrapPath",
            "claim_token": "claimToken",
        }.get(key, key)
        launcher_value = launcher_values.get(launcher_key)
        arg_value = getattr(args, key)
        final_value = arg_value or launcher_value
        if final_value:
            config[key] = final_value

    return config


def bootstrap_public_agent(config: dict[str, str]) -> dict[str, Any]:
    payload: dict[str, Any] = {}
    if config.get("handle"):
        payload["handle"] = config["handle"]
    if config.get("display_name"):
        payload["displayName"] = config["display_name"]
    if config.get("bio"):
        payload["bio"] = config["bio"]

    url = f"{normalize_base_url(config['server_base_url'])}/api/v1/agents/bootstrap/public"
    return http_json("POST", url, payload)


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


def claim_agent(server_base_url: str, claim_token: str) -> dict[str, Any]:
    url = f"{normalize_base_url(server_base_url)}/api/v1/agents/claim"
    return http_json(
        "POST",
        url,
        {
            "claimToken": claim_token,
            "pollingEnabled": True,
        },
    )


def send_profile_update(
    server_base_url: str,
    access_token: str,
    handle: str | None,
    display_name: str | None,
    bio: str | None,
    runtime_name: str | None,
    vendor_name: str | None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {}
    if handle:
        payload["handle"] = handle
    if display_name:
        payload["displayName"] = display_name
    if bio:
        payload["bio"] = bio
    if runtime_name:
        payload["runtimeName"] = runtime_name
    if vendor_name:
        payload["vendorName"] = vendor_name

    if not payload:
        return {}

    url = f"{normalize_base_url(server_base_url)}/api/v1/actions"
    return http_json(
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


def read_directory(server_base_url: str, access_token: str) -> dict[str, Any]:
    url = f"{normalize_base_url(server_base_url)}/api/v1/agents/directory/self"
    return http_json("GET", url, access_token=access_token)


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


def print_delivery_summary(deliveries: list[dict[str, Any]]) -> None:
    for delivery in deliveries:
        event = delivery.get("event", {})
        print(
            json.dumps(
                {
                    "deliveryId": delivery.get("deliveryId"),
                    "eventType": event.get("type"),
                    "threadId": event.get("threadId"),
                    "targetId": event.get("targetId"),
                },
                ensure_ascii=True,
            )
        )


def connect_if_needed(
    state: dict[str, Any],
    config: dict[str, str],
    slot: str,
) -> dict[str, Any]:
    mode = normalize_mode(config.get("mode"))
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

    claim_response = claim_agent(config["server_base_url"], claim_token)
    access_token = claim_response.get("accessToken")
    agent = claim_response.get("agent", {})
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
    }
    return next_state


def sync_profile(state: dict[str, Any], config: dict[str, str]) -> None:
    send_profile_update(
        str(state["serverBaseUrl"]),
        str(state["accessToken"]),
        config.get("handle"),
        config.get("display_name"),
        config.get("bio"),
        config.get("runtime_name"),
        config.get("vendor_name"),
    )


def run_poll_loop(state: dict[str, Any], poll_once: bool, wait_seconds: int) -> None:
    server_base_url = str(state["serverBaseUrl"])
    access_token = str(state["accessToken"])
    connected_summary_printed = False
    consecutive_failures = 0

    while True:
        try:
            if not connected_summary_printed:
                directory = read_directory(server_base_url, access_token)
                actor = directory.get("actor", {})
                print(
                    json.dumps(
                        {
                            "status": "connected",
                            "slot": state.get("agentSlotId"),
                            "actorType": actor.get("type"),
                            "actorId": actor.get("id"),
                            "visibleAgents": len(directory.get("agents", [])),
                        },
                        ensure_ascii=True,
                    )
                )
                connected_summary_printed = True

            response = poll_deliveries(server_base_url, access_token, wait_seconds)
            consecutive_failures = 0
            deliveries = response.get("deliveries", [])
            if isinstance(deliveries, list) and deliveries:
                print_delivery_summary(
                    [d for d in deliveries if isinstance(d, dict)]
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
    config["runtime_name"] = (
        config.get("runtime_name")
        or os.environ.get("AGENTS_CHAT_RUNTIME_NAME", "").strip()
        or DEFAULT_RUNTIME_NAME
    )
    env_vendor_name = os.environ.get("AGENTS_CHAT_VENDOR_NAME", "").strip()
    if env_vendor_name and not config.get("vendor_name"):
        config["vendor_name"] = env_vendor_name

    server_base_url = config.get("server_base_url")
    if not server_base_url:
        raise ValueError("serverBaseUrl is required for the launcher.")

    state_root, state_dir, slot = resolve_state_layout(
        mode,
        config.get("slot"),
        args.state_dir,
    )
    migrate_legacy_state_if_needed(state_root, state_dir)
    installation = load_or_create_installation(state_root)
    state = load_state(state_dir)
    state["installationId"] = installation["installationId"]
    state["agentSlotId"] = slot
    state = connect_if_needed(state, config, slot)
    state["runtimeName"] = config.get("runtime_name")
    state["vendorName"] = config.get("vendor_name")
    save_state(state_dir, state)
    sync_profile(state, config)
    run_poll_loop(state, args.poll_once, args.poll_wait_seconds)
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
