import { test } from "node:test";
import assert from "node:assert/strict";
import { hideThread, readHiddenThreads } from "../lib/hidden-threads.ts";
test("hiding a conversation is isolated to this user and active agent", () => {
  const data = new Map<string, string>();
  const storage = {
    getItem: (key: string) => data.get(key) || null,
    setItem: (key: string, value: string) => {
      data.set(key, value);
    },
  };
  hideThread(storage, "me", "aether", "thread");
  hideThread(storage, "me", "aether", "thread");
  assert.deepEqual(readHiddenThreads(storage, "me", "aether"), ["thread"]);
  assert.deepEqual(readHiddenThreads(storage, "other", "aether"), []);
  assert.deepEqual(readHiddenThreads(storage, "me", "atlas"), []);
  assert.deepEqual(
    readHiddenThreads({ getItem: () => "invalid" }, "me", "aether"),
    [],
  );
  assert.throws(() =>
    hideThread(
      {
        ...storage,
        setItem: () => {
          throw Error("unavailable");
        },
      },
      "me",
      "aether",
      "other",
    ),
  );
});
