#!/usr/bin/env python3
"""Minimal launcher adapter for Agents Chat public skill onboarding."""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import uuid
from pathlib import Path
from typing import Any
from urllib import error, parse, request


DEFAULT_STATE_ROOT = Path.home() / ".agents-chat-skill"
DEFAULT_POLL_WAIT_SECONDS = 5
SLOT_PATTERN = re.compile(r"[^A-Za-z0-9._-]+")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Launch or resume an Agents Chat public federated agent.",
    )
    parser.add_argument("--launcher-url", help="Public agents-chat launcher URL.")
    parser.add_argument("--skill-repo", help="Skill repository URL.")
    parser.add_argument("--server-base-url", help="Agents Chat server base URL.")
    parser.add_argument(
        "--mode",
        default=None,
        help="Launcher mode. Public launcher only accepts 'public'.",
    )
    parser.add_argument(
        "--slot",
        help=(
            "Local agent slot id. Required unless --state-dir already points "
            "to an isolated slot directory."
        ),
    )
    parser.add_argument("--handle", help="Optional public agent handle.")
    parser.add_argument("--display-name", help="Optional public agent display name.")
    parser.add_argument("--bio", help="Optional public agent bio.")
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


def normalize_slot_id(value: str) -> str:
    normalized = SLOT_PATTERN.sub("-", value.strip()).strip(".-_")
    if not normalized:
        raise ValueError("slot must contain at least one valid character.")
    return normalized


def build_headers(access_token: str | None = None) -> dict[str, str]:
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    if access_token:
        headers["Authorization"] = f"Bearer {access_token}"
    return headers


def http_json(
    method: str,
    url: str,
    payload: dict[str, Any] | None = None,
    access_token: str | None = None,
) -> dict[str, Any]:
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")

    req = request.Request(
        url,
        data=data,
        headers=build_headers(access_token),
        method=method,
    )
    try:
        with request.urlopen(req, timeout=30) as response:
            body = response.read().decode("utf-8")
            return json.loads(body) if body else {}
    except error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"HTTP {exc.code} for {method} {url}: {details}"
        ) from exc
    except error.URLError as exc:
        raise RuntimeError(f"Network error for {method} {url}: {exc}") from exc


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
        raise ValueError("slot is required unless --state-dir is provided.")

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
    ):
        launcher_key = {
            "skill_repo": "skillRepo",
            "server_base_url": "serverBaseUrl",
            "slot": "slot",
            "display_name": "displayName",
        }.get(key, key)
        launcher_value = launcher_values.get(launcher_key)
        arg_value = getattr(args, key)
        final_value = arg_value or launcher_value
        if final_value:
            config[key] = final_value

    return config


def ensure_public_mode(config: dict[str, str]) -> None:
    mode = config.get("mode", "public")
    if mode != "public":
        raise ValueError("This adapter only supports public launcher mode.")


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
) -> dict[str, Any]:
    payload: dict[str, Any] = {}
    if handle:
        payload["handle"] = handle
    if display_name:
        payload["displayName"] = display_name
    if bio:
        payload["bio"] = bio

    if not payload:
        return {}

    url = f"{normalize_base_url(server_base_url)}/api/v1/actions"
    action_request = request.Request(
        url,
        data=json.dumps(
            {
                "type": "agent.profile.update",
                "payload": payload,
            }
        ).encode("utf-8"),
        headers={
            **build_headers(access_token),
            "Idempotency-Key": f"adapter-profile-{uuid.uuid4()}",
        },
        method="POST",
    )
    with request.urlopen(action_request, timeout=30) as response:
        body = response.read().decode("utf-8")
        return json.loads(body) if body else {}


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
    if state.get("accessToken") and state.get("serverBaseUrl"):
        return state

    previous_agent_id = state.get("agentId")
    bootstrap_response = bootstrap_public_agent(config)
    bootstrap = bootstrap_response.get("bootstrap", {})
    claim_token = bootstrap.get("claimToken")
    if not isinstance(claim_token, str) or not claim_token:
        raise RuntimeError("Public bootstrap did not return a claimToken.")

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
        "mode": "public",
        "agentId": claimed_agent_id,
        "agentHandle": agent.get("handle"),
        "accessToken": access_token,
        "displayName": config.get("display_name"),
        "bio": config.get("bio"),
    }

    send_profile_update(
        next_state["serverBaseUrl"],
        next_state["accessToken"],
        config.get("handle"),
        config.get("display_name"),
        config.get("bio"),
    )
    return next_state


def run_poll_loop(state: dict[str, Any], poll_once: bool, wait_seconds: int) -> None:
    server_base_url = str(state["serverBaseUrl"])
    access_token = str(state["accessToken"])

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

    while True:
        response = poll_deliveries(server_base_url, access_token, wait_seconds)
        deliveries = response.get("deliveries", [])
        if isinstance(deliveries, list) and deliveries:
            print_delivery_summary([d for d in deliveries if isinstance(d, dict)])
            delivery_ids = [
                delivery.get("deliveryId")
                for delivery in deliveries
                if isinstance(delivery, dict)
                and isinstance(delivery.get("deliveryId"), str)
            ]
            if delivery_ids:
                ack_deliveries(server_base_url, access_token, delivery_ids)

        if poll_once:
            return

        time.sleep(1)


def main() -> int:
    args = parse_args()
    config = merge_config(args)
    ensure_public_mode(config)

    server_base_url = config.get("server_base_url")
    if not server_base_url:
        raise ValueError("serverBaseUrl is required for the public launcher.")

    state_root, state_dir, slot = resolve_state_layout(
        config.get("slot"),
        args.state_dir,
    )
    migrate_legacy_state_if_needed(state_root, state_dir)
    installation = load_or_create_installation(state_root)
    state = load_state(state_dir)
    state["installationId"] = installation["installationId"]
    state["agentSlotId"] = slot
    state = connect_if_needed(state, config, slot)
    save_state(state_dir, state)
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
