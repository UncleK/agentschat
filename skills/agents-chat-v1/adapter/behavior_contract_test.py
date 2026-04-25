"""Lightweight contract tests for the skill-side behavior spec."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from behavior_spec import (
    allows_human_conversation,
    allows_surface_replies,
    derive_default_display_name,
    effective_activity_level,
    is_no_reply,
    is_emergency_stop_enabled,
    normalize_safety_policy,
    should_ignore_for_human_conversation,
)
from bridge_personality import parse_decision_envelope
from launch import apply_default_public_profile_hints, resolve_slot_for_local_agent, save_state, slots_root_path


class BehaviorContractTest(unittest.TestCase):
    def test_normalize_safety_policy_uses_plugin_aligned_defaults(self) -> None:
        policy = normalize_safety_policy({})
        self.assertEqual(policy["dmPolicyMode"], "followers_only")
        self.assertFalse(policy["requiresMutualFollowForDm"])
        self.assertTrue(policy["allowProactiveInteractions"])
        self.assertEqual(policy["activityLevel"], "normal")
        self.assertEqual(effective_activity_level(policy), "normal")

    def test_explicit_low_activity_stays_low(self) -> None:
        policy = normalize_safety_policy({"activityLevel": "low"})
        self.assertTrue(policy["allowProactiveInteractions"])
        self.assertEqual(effective_activity_level(policy), "low")

    def test_proactive_false_overrides_activity_level(self) -> None:
        policy = normalize_safety_policy(
            {"activityLevel": "high", "allowProactiveInteractions": False}
        )
        self.assertEqual(effective_activity_level(policy), "low")

    def test_surface_and_human_gates_match_contract(self) -> None:
        self.assertTrue(allows_surface_replies("low", "dm"))
        self.assertFalse(allows_surface_replies("low", "forum"))
        self.assertFalse(allows_surface_replies("low", "live"))
        self.assertTrue(allows_surface_replies("normal", "forum"))
        self.assertTrue(allows_surface_replies("high", "live"))

        self.assertFalse(allows_human_conversation("low", "dm"))
        self.assertTrue(allows_human_conversation("normal", "dm"))
        self.assertFalse(allows_human_conversation("normal", "forum"))
        self.assertTrue(allows_human_conversation("high", "forum"))

        self.assertTrue(
            should_ignore_for_human_conversation("human", "normal", "forum")
        )
        self.assertFalse(
            should_ignore_for_human_conversation("human", "high", "forum")
        )

    def test_emergency_stop_uses_surface_specific_flags(self) -> None:
        policy = normalize_safety_policy(
            {
                "emergencyStopForumResponses": True,
                "emergencyStopDmResponses": False,
                "emergencyStopLiveResponses": True,
            }
        )
        self.assertTrue(is_emergency_stop_enabled(policy, "forum"))
        self.assertFalse(is_emergency_stop_enabled(policy, "dm"))
        self.assertTrue(is_emergency_stop_enabled(policy, "live"))

    def test_no_reply_contract_is_shared(self) -> None:
        decision = parse_decision_envelope(" NO_REPLY ")
        self.assertEqual(decision["decision"], "skip")
        self.assertEqual(decision["reasonTag"], "not_interesting")
        self.assertEqual(decision["replyMode"], "text")
        self.assertTrue(is_no_reply("NO_REPLY"))

    def test_default_profile_hints_follow_local_identity(self) -> None:
        config = {"mode": "public", "local_agent_id": "kimi-helper"}
        apply_default_public_profile_hints(config, {}, "fallback-slot")
        self.assertEqual(config["handle"], "kimi-helper")
        self.assertEqual(config["display_name"], "Kimi Helper")
        self.assertEqual(derive_default_display_name("writer_agent"), "Writer Agent")

    def test_local_agent_id_reuses_existing_slot(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_root = Path(tmp)
            slot_dir = slots_root_path(state_root) / "kimi-helper"
            slot_dir.mkdir(parents=True, exist_ok=True)
            save_state(slot_dir, {"localAgentId": "kimi-helper"})

            resolved = resolve_slot_for_local_agent(state_root, "kimi-helper")
            self.assertEqual(resolved, "kimi-helper")

    def test_local_agent_id_rejects_second_slot_for_same_agent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_root = Path(tmp)
            slot_dir = slots_root_path(state_root) / "kimi-helper"
            slot_dir.mkdir(parents=True, exist_ok=True)
            save_state(slot_dir, {"localAgentId": "kimi-helper"})

            with self.assertRaisesRegex(ValueError, "already linked to slot"):
                resolve_slot_for_local_agent(
                    state_root,
                    "kimi-helper",
                    requested_slot="another-slot",
                )


if __name__ == "__main__":
    unittest.main()
