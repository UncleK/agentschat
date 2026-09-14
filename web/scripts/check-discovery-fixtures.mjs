import assert from "node:assert/strict";
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { fileURLToPath } from "node:url";

// Exercises rendered public content and outages against loopback-only fixtures.
// Requires npm run build. Starts and stops only its own Web child process.
let mode = "content";
const ids = [
  "10000000-0000-4000-8000-000000000001",
  "10000000-0000-4000-8000-000000000002",
];
const fixture = createServer((req, res) => {
  res.setHeader("Content-Type", "application/json");
  if (mode === "outage") {
    res.writeHead(503);
    res.end("{}");
    return;
  }
  const url = new URL(req.url, "http://fixture.invalid");
  let value;
  if (url.pathname.endsWith("/public/index")) {
    const kind = url.searchParams.get("type");
    const index = url.searchParams.has("cursor") ? 1 : 0;
    value = {
      items: [
        {
          id: ids[index],
          handle: `fixture-agent-${index}`,
          updatedAt: "2026-09-14T00:00:00.000Z",
        },
      ],
      nextCursor:
        mode === "cycle" && kind === "forum"
          ? "repeated"
          : index === 0
            ? "second"
            : null,
    };
  } else if (url.pathname.endsWith("/content/public/forum/topics")) {
    value = {
      topics: [
        {
          threadId: ids[0],
          title: 'Public <script>alert("fixture")</script>',
          summary: "Inspect this public fixture evidence.",
          authorName: "Fixture researcher",
          createdAt: "2026-09-14T00:00:00.000Z",
        },
      ],
      nextCursor: null,
    };
  } else if (url.pathname.endsWith("/debates")) {
    value = {
      sessions: [
        {
          debateSessionId: ids[1],
          topic: "Fixture debate",
          proStance: "A public position",
          conStance: "Another public position",
        },
      ],
      nextCursor: null,
    };
  } else {
    res.writeHead(404);
    value = {};
  }
  res.end(JSON.stringify(value));
});
fixture.listen(0, "127.0.0.1");
await once(fixture, "listening");
const portProbe = createServer();
portProbe.listen(0, "127.0.0.1");
await once(portProbe, "listening");
const port = portProbe.address().port;
await new Promise((resolve) => portProbe.close(resolve));
const base = `http://127.0.0.1:${port}`;
const cwd = fileURLToPath(new URL("..", import.meta.url));
const env = {
  ...process.env,
  PORT: String(port),
  WEB_HOST: "127.0.0.1",
  NEXT_PUBLIC_SITE_URL: "https://agentschat.app",
  API_ORIGIN: `http://127.0.0.1:${fixture.address().port}`,
  DISCOVERY_BASE_URL: base,
};
const child = spawn(process.execPath, ["scripts/start.mjs"], {
  cwd,
  env,
  windowsHide: true,
  stdio: ["ignore", "pipe", "pipe"],
});
let log = "";
child.stdout.on("data", (data) => {
  log += data;
});
child.stderr.on("data", (data) => {
  log += data;
});
try {
  let ready = false;
  for (let i = 0; i < 100; i++) {
    if (child.exitCode !== null) throw new Error(log);
    try {
      const r = await fetch(base + "/robots.txt");
      if (r.ok) {
        ready = true;
        break;
      }
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  assert.ok(ready, "Fixture Web server starts");
  for (const path of ["/", "/watch", "/en", "/en/watch"]) {
    const response = await fetch(base + path);
    assert.equal(response.status, 200);
    const body = await response.text();
    const markup = body.replace(/<script\b[^>]*>[\s\S]*?<\/script>/g, "");
    assert.ok(
      markup.includes(
        `href="${path.startsWith("/en") ? "/en" : ""}/forum/${ids[0]}"`,
      ),
      "Public topic has a crawlable detail link",
    );
    assert.ok(
      markup.includes(
        `href="${path.startsWith("/en") ? "/en" : ""}/live/${ids[1]}"`,
      ),
      "Debate has a crawlable detail link",
    );
    assert.ok(markup.includes("Fixture researcher"));
    assert.ok(markup.includes("&lt;script&gt;"), "User title is escaped");
    assert.ok(
      !body.includes('<script>alert("fixture")</script>'),
      "User text cannot become script",
    );
  }
  let sitemap = await (await fetch(base + "/sitemap.xml")).text();
  for (const id of ids)
    assert.ok(sitemap.includes(`/forum/${id}`), "Index follows nextCursor");
  assert.ok(sitemap.includes("/agents/fixture-agent-1"));
  console.log(
    "PASS non-empty public records render in HTML, author text is escaped, sitemap follows pagination",
  );
  mode = "cycle";
  sitemap = await (await fetch(base + "/sitemap.xml")).text();
  assert.ok(sitemap.includes("/en/for-agents"));
  assert.ok(sitemap.includes("/agents/fixture-agent-1"));
  assert.ok(!sitemap.includes(`/forum/${ids[0]}`));
  console.log(
    "PASS repeated cursor stops its index; other public sections remain discoverable",
  );
  mode = "outage";
  const check = spawn(
    process.execPath,
    ["scripts/check-discovery.mjs", "--expect-unavailable"],
    { cwd, env, windowsHide: true, stdio: "inherit" },
  );
  const [code] = await once(check, "exit");
  assert.equal(code, 0, "Metadata and outage acceptance check");
} finally {
  const exited = once(child, "exit");
  if (child.exitCode === null) {
    child.kill();
    await exited;
  }
  await new Promise((resolve) => fixture.close(resolve));
}
