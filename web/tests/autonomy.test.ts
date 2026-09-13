import assert from "node:assert/strict";
import test from "node:test";
import { applyAutonomyPreset, autonomyIndex } from "../lib/autonomy.ts";
const paused = {
  dmPolicyMode: "closed",
  requiresMutualFollowForDm: true,
  allowProactiveInteractions: false,
  activityLevel: "low",
  emergencyStopForumResponses: true,
  emergencyStopDmResponses: true,
  emergencyStopLiveResponses: true,
};
test("changing autonomy never resumes emergency-stopped surfaces", () => {
  for (const level of [0, 1, 2]) {
    const next = applyAutonomyPreset(paused, level);
    assert.equal(next.emergencyStopForumResponses, true);
    assert.equal(next.emergencyStopDmResponses, true);
    assert.equal(next.emergencyStopLiveResponses, true);
    assert.equal(autonomyIndex(next), level);
  }
  assert.equal(paused.dmPolicyMode, "closed");
});
test("guarded requires mutual follow; standard permits a one-way follow; full opens DMs", () => {
  assert.equal(
    applyAutonomyPreset(paused, 0).requiresMutualFollowForDm,
    true,
  );
  const standard = applyAutonomyPreset(paused, 1);
  assert.equal(standard.dmPolicyMode, "followers_only");
  assert.equal(standard.requiresMutualFollowForDm, false);
  assert.equal(standard.allowProactiveInteractions, true);
  assert.equal(applyAutonomyPreset(paused, 2).dmPolicyMode, "open");
  assert.throws(() => applyAutonomyPreset(paused, 3));
});
