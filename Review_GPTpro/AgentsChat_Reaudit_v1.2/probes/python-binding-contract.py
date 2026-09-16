#!/usr/bin/env python3
"""Capture the unchanged generic adapter's submission, without network access.

Source: skills/agents-chat-v1/adapter/launch.py, commit
7314f18a60843cc72c7566a817e7264fbe12fe4e, submit_claim_confirmation.
The function below is transcribed from the fetched source. http_json is a stub.
This is NOT a Python-adapter-to-NestJS integration test.
"""
import json
import uuid
from typing import Any

calls: list[dict[str, Any]] = []

def normalize_base_url(value: str) -> str:
    return value.rstrip("/")

def http_json(method, url, payload, **kwargs):
    # No network, no real credentials. Observe request construction only.
    calls.append({"method": method, "url": url, "payload": payload,
                  "has_agent_bearer": bool(kwargs.get("access_token")),
                  "header_names": sorted(kwargs.get("extra_headers", {}))})
    return {"id": "synthetic-action", "status": "accepted"}

# START exact source function

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

# END exact source function

if __name__ == "__main__":
    submit_claim_confirmation("https://synthetic.invalid/", "synthetic-token",
                              "synthetic-request", "synthetic-challenge")
    assert len(calls) == 1
    assert calls[0]["payload"]["type"] == "claim.confirm"
    assert calls[0]["url"].endswith("/api/v1/actions")
    print(json.dumps({
        "commit": "7314f18a60843cc72c7566a817e7264fbe12fe4e",
        "method": "extracted adapter function, request construction only",
        "networkRequests": 0,
        "observed": calls[0],
        "server_source_crosscheck": {
            "file": "server/src/modules/federation/federation.service.ts",
            "handler": "handleClaimConfirmation",
            "always_throws": "control_authorization_required",
            "note": "Server refusal verified in fetched source, not invoked over HTTP here."
        }
    }, ensure_ascii=False, indent=2))
