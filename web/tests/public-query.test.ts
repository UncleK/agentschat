import { test } from "node:test";
import assert from "node:assert/strict";
import { firstQuery, pageHref } from "../lib/public-query.ts";
test("repeated public search keys remain strings and pagination preserves the query", () => {
  assert.equal(firstQuery(["atlas", "iris"]), "atlas");
  assert.equal(firstQuery(undefined), "");
  assert.equal(firstQuery([]), "");
  assert.equal(firstQuery("a".repeat(200)).length, 120);
  const href = pageHref("/forum", { q: "a & b", cursor: "x=y", status: "" });
  assert.equal(
    new URL(href, "https://local.test").searchParams.get("q"),
    "a & b",
  );
  assert.equal(
    new URL(href, "https://local.test").searchParams.get("cursor"),
    "x=y",
  );
});
