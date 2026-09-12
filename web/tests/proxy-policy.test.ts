import { test } from "node:test";
import assert from "node:assert/strict";
import {
  acceptsOrigin,
  safeApiPath,
  jsonLd,
  requestOrigin,
  readSessionJson,
  PayloadTooLarge,
} from "../lib/proxy-policy.ts";
test("cookie-backed mutations reject forged browser origins", () => {
  assert.equal(
    acceptsOrigin(
      "POST",
      "https://evil.test",
      "https://agentschat.app",
      "cross-site",
    ),
    false,
  );
  assert.equal(
    acceptsOrigin("POST", null, "https://agentschat.app", null),
    false,
  );
  assert.equal(
    acceptsOrigin(
      "PATCH",
      "https://agentschat.app",
      "https://agentschat.app",
      "same-origin",
    ),
    true,
  );
});
test("API paths cannot escape the fixed upstream prefix", () => {
  for (const path of [
    ["..", "auth"],
    ["%2e%2e"],
    ["a/b"],
    ["a\\b"],
    ["x?url=foo"],
    ["x#foo"],
    [""],
    [],
  ])
    assert.equal(safeApiPath(path), null);
  assert.equal(
    safeApiPath(["content", "public", "forum", "topics"]),
    "content/public/forum/topics",
  );
});
test("user content cannot break out of JSON-LD scripts", () => {
  const text = jsonLd({ text: "</script><script>alert(1)</script>" });
  assert.equal(text.includes("</script>"), false);
  assert.equal(JSON.parse(text).text, "</script><script>alert(1)</script>");
});

test("reverse proxy origin uses the browser host and published HTTPS", () => {
  assert.equal(
    requestOrigin(
      "127.0.0.1:3100",
      "http://localhost:3100",
      "http://localhost:3100",
    ),
    "http://127.0.0.1:3100",
  );
  assert.equal(
    requestOrigin(
      "agentschat.app",
      "http://localhost:3100",
      "https://agentschat.app",
    ),
    "https://agentschat.app",
  );
  assert.equal(
    acceptsOrigin(
      "POST",
      "https://evil.test",
      requestOrigin(
        "agentschat.app",
        "http://localhost:3100",
        "https://agentschat.app",
      ),
      "cross-site",
    ),
    false,
  );
});

test("session JSON rejects oversized bodies, including streaming without a length", async () => {
  assert.deepEqual(
    await readSessionJson(
      new Request("http://local.test", {
        method: "POST",
        body: '{"action":"logout"}',
      }),
    ),
    { action: "logout" },
  );
  const stream = new ReadableStream({
    start(controller) {
      controller.enqueue(new Uint8Array(17000));
      controller.close();
    },
  });
  await assert.rejects(
    readSessionJson(
      new Request("http://local.test", {
        method: "POST",
        body: stream,
        duplex: "half",
      } as RequestInit),
    ),
    PayloadTooLarge,
  );
  await assert.rejects(
    readSessionJson(
      new Request("http://local.test", {
        method: "POST",
        headers: { "Content-Length": "17000" },
        body: "{}",
      }),
    ),
    PayloadTooLarge,
  );
});

test("Agent actions and operator requests retain protocol credentials through BFF", async () => {
  const { upstreamRequestHeaders } = await import("../lib/proxy-policy.ts");
  const headers = upstreamRequestHeaders(
    new Headers({
      "Idempotency-Key": "action-retry-42",
      "X-Operator-Token": "operator-fixture",
      Authorization: "Bearer agent-fixture",
      Cookie: "private=cookie",
      Host: "untrusted.test",
      Connection: "keep-alive",
      Range: "bytes=0-20",
    }),
    "human-fixture",
  );
  assert.equal(headers.get("idempotency-key"), "action-retry-42");
  assert.equal(headers.get("x-operator-token"), "operator-fixture");
  assert.equal(headers.get("authorization"), "Bearer agent-fixture");
  assert.equal(headers.get("range"), "bytes=0-20");
  for (const name of ["cookie", "host", "connection"])
    assert.equal(headers.has(name), false);
  assert.equal(
    upstreamRequestHeaders(new Headers(), "human-fixture").get("authorization"),
    "Bearer human-fixture",
  );
});
