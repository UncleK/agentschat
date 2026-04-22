"""Worker-level contract tests for the generic Agents Chat skill worker."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from behavior_spec import normalize_safety_policy
from bridge_personality import normalize_personality
import worker


class FakeRuntimeDriver:
    def __init__(self, reply_results: list[dict[str, str]] | None = None) -> None:
        self.reply_results = list(reply_results or [])
        self.reply_calls: list[dict[str, object]] = []
        self.profile_calls: list[dict[str, object]] = []

    def invoke_reply_or_turn(
        self,
        *,
        session_key: str,
        input_payload: dict[str, object],
        max_chars: int,
    ) -> dict[str, str]:
        self.reply_calls.append(
            {
                "session_key": session_key,
                "input_payload": input_payload,
                "max_chars": max_chars,
            }
        )
        if not self.reply_results:
            return {
                "decision": "skip",
                "reasonTag": "not_interesting",
                "replyText": "",
            }
        return self.reply_results.pop(0)

    def invoke_profile_bootstrap(
        self,
        *,
        session_key: str,
        input_payload: dict[str, object],
    ) -> dict[str, object]:
        self.profile_calls.append(
            {
                "session_key": session_key,
                "input_payload": input_payload,
            }
        )
        return normalize_personality({})


class WorkerContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state_dir = Path(self.tmp.name)
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.state = {
            "serverBaseUrl": "https://agentschat.app",
            "accessToken": "token-1",
            "agentId": "agent-self",
            "localAgentId": "writer",
            "displayName": "Writer",
            "agentHandle": "writer",
            "bio": "Helpful writer agent.",
            "profileTags": ["writing"],
            "personality": normalize_personality({}),
        }
        self.args = SimpleNamespace(
            session_prefix="agentschat",
            history_limit=24,
            reply_max_chars=4000,
            action_timeout_seconds=5,
            dry_run=False,
            print_prompt=False,
            ack_unhandled=True,
        )

    def run_batch(
        self,
        deliveries: list[dict[str, object]],
        runtime_driver: FakeRuntimeDriver,
        *,
        safety_policy: dict[str, object] | None = None,
        read_dm_thread_messages_result: dict[str, object] | None = None,
        read_forum_topic_result: dict[str, object] | None = None,
        read_debate_result: dict[str, object] | None = None,
    ) -> tuple[list[dict[str, object]], list[list[str]]]:
        submitted_actions: list[dict[str, object]] = []
        acked_batches: list[list[str]] = []

        def fake_submit_action(
            _server_base_url: str,
            _access_token: str,
            action_body: dict[str, object],
            idempotency_key: str | None = None,
        ) -> dict[str, str]:
            submitted_actions.append(
                {
                    "action_body": action_body,
                    "idempotency_key": idempotency_key,
                }
            )
            return {"id": f"act-{len(submitted_actions)}"}

        def fake_wait_for_action_completion(
            _server_base_url: str,
            _access_token: str,
            _action_id: str,
            _timeout_seconds: int,
        ) -> dict[str, str]:
            return {"status": "succeeded"}

        def fake_ack_deliveries(
            _server_base_url: str,
            _access_token: str,
            delivery_ids: list[str],
        ) -> dict[str, object]:
            acked_batches.append(list(delivery_ids))
            return {"deliveryIds": delivery_ids}

        with (
            patch.object(
                worker,
                "load_worker_safety_policy",
                return_value=safety_policy or normalize_safety_policy({}),
            ),
            patch.object(
                worker,
                "read_dm_thread_messages",
                return_value=read_dm_thread_messages_result or {"messages": []},
            ),
            patch.object(
                worker,
                "read_forum_topic",
                return_value=read_forum_topic_result or {"topic": {}},
            ),
            patch.object(
                worker,
                "read_debate",
                return_value=read_debate_result or {"session": {}},
            ),
            patch.object(worker, "submit_action", side_effect=fake_submit_action),
            patch.object(
                worker,
                "wait_for_action_completion",
                side_effect=fake_wait_for_action_completion,
            ),
            patch.object(worker, "ack_deliveries", side_effect=fake_ack_deliveries),
            patch.object(worker, "print_json", return_value=None),
            patch.object(worker.time, "sleep", return_value=None),
        ):
            succeeded = worker.handle_delivery_batch(
                deliveries,
                slot="writer",
                state_dir=self.state_dir,
                state=dict(self.state),
                runtime_driver=runtime_driver,
                args=self.args,
                instruction_text="Be helpful.",
            )
        self.assertTrue(succeeded)
        return submitted_actions, acked_batches

    def test_dm_received_creates_dm_send_action(self) -> None:
        runtime = FakeRuntimeDriver(
            [
                {
                    "decision": "reply",
                    "reasonTag": "useful",
                    "replyText": "I can help with that.",
                }
            ]
        )
        delivery = {
            "deliveryId": "del-1",
            "event": {
                "type": "dm.received",
                "threadId": "dm-1",
                "actorType": "agent",
                "actorAgentId": "agent-other",
                "actorDisplayName": "Other Agent",
                "content": "Can you help me debug this issue?",
                "occurredAt": "2026-04-22T10:00:00.000Z",
            },
        }
        messages = {
            "messages": [
                {
                    "occurredAt": "2026-04-22T10:00:00.000Z",
                    "content": "Can you help me debug this issue?",
                    "actor": {
                        "id": "agent-other",
                        "type": "agent",
                        "displayName": "Other Agent",
                    },
                }
            ]
        }

        submitted_actions, acked_batches = self.run_batch(
            [delivery],
            runtime,
            read_dm_thread_messages_result=messages,
        )

        self.assertEqual(len(submitted_actions), 1)
        action = submitted_actions[0]["action_body"]
        self.assertEqual(action["type"], "dm.send")
        self.assertEqual(action["payload"]["threadId"], "dm-1")
        self.assertEqual(action["payload"]["targetType"], "agent")
        self.assertEqual(action["payload"]["targetId"], "agent-other")
        self.assertEqual(action["payload"]["content"], "I can help with that.")
        self.assertEqual(acked_batches, [["del-1"]])
        self.assertEqual(runtime.reply_calls[0]["input_payload"]["surface"], "dm")

    def test_forum_second_level_reply_skips_without_runtime_call(self) -> None:
        runtime = FakeRuntimeDriver()
        delivery = {
            "deliveryId": "del-2",
            "event": {
                "type": "forum.reply.create",
                "threadId": "topic-1",
                "id": "reply-child",
                "parentEventId": "reply-root",
                "actorType": "agent",
                "actorAgentId": "agent-other",
                "actorDisplayName": "Other Agent",
                "content": "One more nested follow-up.",
                "occurredAt": "2026-04-22T10:00:00.000Z",
            },
        }
        topic = {
            "topic": {
                "id": "topic-1",
                "rootEventId": "root-1",
                "title": "Topic",
                "authorName": "Alice",
                "rootBody": "Root body",
                "replies": [
                    {
                        "id": "reply-root",
                        "authorType": "agent",
                        "authorAgentId": "agent-other",
                        "authorName": "Other Agent",
                        "body": "Top-level reply",
                        "children": [
                            {
                                "id": "reply-child",
                                "authorType": "agent",
                                "authorAgentId": "agent-third",
                                "authorName": "Third Agent",
                                "body": "Nested reply",
                                "children": [],
                            }
                        ],
                    }
                ],
            }
        }

        submitted_actions, acked_batches = self.run_batch(
            [delivery],
            runtime,
            read_forum_topic_result=topic,
        )

        self.assertEqual(submitted_actions, [])
        self.assertEqual(runtime.reply_calls, [])
        self.assertEqual(acked_batches, [["del-2"]])

    def test_forum_first_level_reply_creates_action(self) -> None:
        runtime = FakeRuntimeDriver(
            [
                {
                    "decision": "reply",
                    "reasonTag": "useful",
                    "replyText": "Here is a sharper framing.",
                }
            ]
        )
        delivery = {
            "deliveryId": "del-3",
            "event": {
                "type": "forum.reply.create",
                "threadId": "topic-2",
                "id": "reply-top",
                "parentEventId": "root-2",
                "actorType": "agent",
                "actorAgentId": "agent-other",
                "actorDisplayName": "Other Agent",
                "content": "Here is one angle, but what about the tradeoff?",
                "occurredAt": "2026-04-22T10:00:00.000Z",
            },
        }
        topic = {
            "topic": {
                "id": "topic-2",
                "rootEventId": "root-2",
                "title": "Topic",
                "authorName": "Alice",
                "rootBody": "Root body",
                "replies": [
                    {
                        "id": "reply-top",
                        "authorType": "agent",
                        "authorAgentId": "agent-other",
                        "authorName": "Other Agent",
                        "body": "Here is one angle, but what about the tradeoff?",
                        "children": [],
                    }
                ],
            }
        }

        submitted_actions, _acked_batches = self.run_batch(
            [delivery],
            runtime,
            read_forum_topic_result=topic,
        )

        self.assertEqual(len(submitted_actions), 1)
        action = submitted_actions[0]["action_body"]
        self.assertEqual(action["type"], "forum.reply.create")
        self.assertEqual(action["payload"]["threadId"], "topic-2")
        self.assertEqual(action["payload"]["parentEventId"], "reply-top")
        self.assertEqual(action["payload"]["content"], "Here is a sharper framing.")

    def test_live_spectator_reply_creates_action(self) -> None:
        runtime = FakeRuntimeDriver(
            [
                {
                    "decision": "reply",
                    "reasonTag": "novelty",
                    "replyText": "That reframes the audience question well.",
                }
            ]
        )
        delivery = {
            "deliveryId": "del-4",
            "event": {
                "type": "debate.spectator.post",
                "targetId": "debate-1",
                "actorType": "agent",
                "actorAgentId": "agent-other",
                "actorDisplayName": "Other Agent",
                "content": "How does this change the audience takeaway?",
                "occurredAt": "2026-04-22T10:00:00.000Z",
            },
        }
        debate = {
            "session": {
                "debateSessionId": "debate-1",
                "topic": "AI policy",
                "status": "live",
                "proStance": "Regulate",
                "conStance": "Do not regulate",
                "formalTurns": [],
                "spectatorFeed": [],
                "seats": [],
            }
        }

        submitted_actions, _acked_batches = self.run_batch(
            [delivery],
            runtime,
            read_debate_result=debate,
        )

        self.assertEqual(len(submitted_actions), 1)
        action = submitted_actions[0]["action_body"]
        self.assertEqual(action["type"], "debate.spectator.post")
        self.assertEqual(action["payload"]["debateSessionId"], "debate-1")
        self.assertEqual(
            action["payload"]["content"],
            "That reframes the audience question well.",
        )

    def test_debate_turn_assignment_submits_turn(self) -> None:
        runtime = FakeRuntimeDriver(
            [
                {
                    "decision": "reply",
                    "reasonTag": "useful",
                    "replyText": "The strongest rebuttal is about incentives.",
                }
            ]
        )
        delivery = {
            "deliveryId": "del-5",
            "event": {
                "type": "debate.turn.assigned",
                "targetId": "debate-2",
                "metadata": {
                    "agentId": "agent-self",
                    "seatId": "seat-pro",
                    "turnNumber": 2,
                    "stance": "pro",
                    "deadlineAt": "2026-04-22T10:05:00.000Z",
                },
            },
        }
        debate = {
            "session": {
                "debateSessionId": "debate-2",
                "topic": "AI policy",
                "proStance": "Regulate",
                "conStance": "Do not regulate",
                "formalTurns": [],
                "spectatorFeed": [],
                "seats": [
                    {
                        "id": "seat-pro",
                        "agentId": "agent-self",
                        "agent": {"id": "agent-self", "displayName": "Writer"},
                    }
                ],
            }
        }

        submitted_actions, _acked_batches = self.run_batch(
            [delivery],
            runtime,
            read_debate_result=debate,
        )

        self.assertEqual(len(submitted_actions), 1)
        action = submitted_actions[0]["action_body"]
        self.assertEqual(action["type"], "debate.turn.submit")
        self.assertEqual(action["payload"]["debateSessionId"], "debate-2")
        self.assertEqual(action["payload"]["seatId"], "seat-pro")
        self.assertEqual(action["payload"]["turnNumber"], 2)
        self.assertEqual(
            action["payload"]["content"],
            "The strongest rebuttal is about incentives.",
        )

    def test_debate_turn_skip_when_runtime_returns_no_reply(self) -> None:
        runtime = FakeRuntimeDriver(
            [
                {
                    "decision": "skip",
                    "reasonTag": "not_interesting",
                    "replyText": "",
                }
            ]
        )
        delivery = {
            "deliveryId": "del-6",
            "event": {
                "type": "debate.turn.assigned",
                "targetId": "debate-3",
                "metadata": {
                    "agentId": "agent-self",
                    "seatId": "seat-con",
                    "turnNumber": 4,
                    "stance": "con",
                    "deadlineAt": "2026-04-22T10:05:00.000Z",
                },
            },
        }
        debate = {
            "session": {
                "debateSessionId": "debate-3",
                "topic": "AI policy",
                "proStance": "Regulate",
                "conStance": "Do not regulate",
                "formalTurns": [],
                "spectatorFeed": [],
                "seats": [
                    {
                        "id": "seat-con",
                        "agentId": "agent-self",
                        "agent": {"id": "agent-self", "displayName": "Writer"},
                    }
                ],
            }
        }

        submitted_actions, _acked_batches = self.run_batch(
            [delivery],
            runtime,
            read_debate_result=debate,
        )

        self.assertEqual(submitted_actions, [])

    def test_emergency_stop_overrides_high_activity_for_debate_turn(self) -> None:
        runtime = FakeRuntimeDriver(
            [
                {
                    "decision": "reply",
                    "reasonTag": "useful",
                    "replyText": "This should not be used.",
                }
            ]
        )
        delivery = {
            "deliveryId": "del-7",
            "event": {
                "type": "debate.turn.assigned",
                "targetId": "debate-4",
                "metadata": {
                    "agentId": "agent-self",
                    "seatId": "seat-pro",
                    "turnNumber": 1,
                    "stance": "pro",
                },
            },
        }
        debate = {
            "session": {
                "debateSessionId": "debate-4",
                "topic": "AI policy",
                "proStance": "Regulate",
                "conStance": "Do not regulate",
                "formalTurns": [],
                "spectatorFeed": [],
                "seats": [],
            }
        }

        submitted_actions, _acked_batches = self.run_batch(
            [delivery],
            runtime,
            safety_policy=normalize_safety_policy(
                {
                    "activityLevel": "high",
                    "emergencyStopLiveResponses": True,
                }
            ),
            read_debate_result=debate,
        )

        self.assertEqual(submitted_actions, [])
        self.assertEqual(runtime.reply_calls, [])


if __name__ == "__main__":
    unittest.main()
