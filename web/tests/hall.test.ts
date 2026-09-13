import { test } from "node:test";
import assert from "node:assert/strict";
import {
  hallMessageReasons,
  hallRelationship,
  hallRuntime,
  searchHall,
  hallColumns,
  type HallAgent,
} from "../lib/hall.ts";
const agent: HallAgent = {
  id: "target",
  handle: "stable-handle",
  displayName: "智能体",
  bio: "简介",
  avatarUrl: null,
  avatarEmoji: null,
  status: "online",
  profileTags: ["研究"],
  followerCount: 1,
  runtimeName: null,
  vendorName: null,
  dmPolicy: {
    directMessageAllowed: true,
    requiresFollowForDm: true,
    requiresMutualFollowForDm: true,
    blockedReasons: [],
  },
  relationship: { viewerFollowsAgent: false, agentFollowsViewer: false },
};
test("acceptance does not bypass follow, reciprocal follow or offline checks; owner chat stays independent", () => {
  assert.equal(hallMessageReasons(agent).length, 2);
  const followed = {
    ...agent,
    relationship: { viewerFollowsAgent: true, agentFollowsViewer: false },
  };
  assert.equal(hallMessageReasons(followed).length, 1);
  const mutual = {
    ...agent,
    relationship: { viewerFollowsAgent: true, agentFollowsViewer: true },
  };
  assert.deepEqual(hallMessageReasons(mutual), []);
  assert.equal(hallMessageReasons({ ...mutual, status: "offline" }).length, 1);
  assert.equal(
    hallMessageReasons({
      ...mutual,
      dmPolicy: { directMessageAllowed: false, requiresFollowForDm: false },
    }).length,
    1,
  );
  assert.deepEqual(
    hallMessageReasons({ ...agent, status: "offline" }, true),
    [],
  );
  assert.equal(hallRelationship(followed, false), "当前智能体已关注对方");
  assert.equal(
    hallRelationship(
      {
        ...agent,
        relationship: { viewerFollowsAgent: false, agentFollowsViewer: true },
      },
      false,
    ),
    "对方已关注你的当前智能体",
  );
});
test("Hall search includes stable handles, bios, metadata headlines and skills without changing directory order", () => {
  const second = {
    ...agent,
    id: "second",
    handle: "second",
    profileMetadata: { headline: "推理" },
  };
  assert.deepEqual(searchHall([agent, second], " STABLE-HANDLE "), [agent]);
  assert.deepEqual(searchHall([agent, second], "研究"), [agent, second]);
  assert.deepEqual(searchHall([agent, second], "推理"), [second]);
  assert.deepEqual(hallColumns([agent, second], 2), [[agent], [second]]);
  assert.equal(
    hallRuntime({ ...agent, profileMetadata: { model: "test-model" } }),
    "test-model",
  );
});
