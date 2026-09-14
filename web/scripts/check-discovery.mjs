import assert from "node:assert/strict";

// Read-only HTTP acceptance check against a running production build.
// No account creation, connections, private API reads or writes.
const base = process.env.DISCOVERY_BASE_URL || "http://127.0.0.1:3101";
const origin = (
  process.env.NEXT_PUBLIC_SITE_URL || "https://agentschat.app"
).replace(/\/$/, "");
const unavailable = process.argv.includes("--expect-unavailable");
const pages = [
  "/",
  "/for-agents",
  "/watch",
  "/en",
  "/en/for-agents",
  "/en/watch",
  "/docs",
  "/en/docs",
  "/guide",
  "/en/guide",
  "/privacy",
  "/en/privacy",
  "/agents",
  "/en/agents",
  "/forum",
  "/en/forum",
  "/live",
  "/en/live",
];
const decode = (text) =>
  text
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#x27;|&#39;|&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
const attrs = (tag) =>
  Object.fromEntries(
    [...tag.matchAll(/([\w:-]+)="([^"]*)"/g)].map(([, k, v]) => [
      k.toLowerCase(),
      decode(v),
    ]),
  );
async function read(path, headers = {}) {
  const response = await fetch(base + path, {
    headers,
    signal: AbortSignal.timeout(20000),
  });
  assert.equal(response.status, 200, path);
  return { response, body: await response.text() };
}
const titles = new Set();
for (const path of pages) {
  const { response, body } = await read(path);
  assert.match(response.headers.get("content-type"), /text\/html/);
  const title = decode(body.match(/<title>([^<]*)<\/title>/)?.[1] || "");
  assert.match(title, /Agents Chat/, `${path}: brand in title`);
  assert.ok(!titles.has(title), `${path}: unique title`);
  titles.add(title);
  if (!path.endsWith("/live"))
    assert.equal(
      [...body.matchAll(/<h1(?:\s|>)/g)].length,
      1,
      `${path}: one H1 without JS`,
    );
  const meta = [...body.matchAll(/<meta\b[^>]*>/g)].map(([t]) => attrs(t));
  assert.ok(
    meta.find((m) => m.name === "description")?.content.length > 15,
    `${path}: description`,
  );
  assert.ok(
    !meta.some((m) => m.name === "robots" && m.content.includes("noindex")),
    `${path}: indexable`,
  );
  const links = [...body.matchAll(/<link\b[^>]*>/g)].map(([t]) => attrs(t));
  const absolute = origin + (path === "/" ? "/" : path);
  assert.equal(
    new URL(links.find((l) => l.rel === "canonical")?.href).href,
    new URL(absolute).href,
    `${path}: canonical`,
  );
  const zh =
    path === "/en" ? "/" : path.startsWith("/en/") ? path.slice(3) : path;
  const en = zh === "/" ? "/en" : "/en" + zh;
  for (const [language, href] of [
    ["zh-CN", zh],
    ["en", en],
    ["x-default", en],
  ]) {
    assert.equal(
      new URL(links.find((l) => l.hreflang === language)?.href).href,
      new URL(origin + href).href,
      `${path}: reciprocal ${language}`,
    );
  }
  assert.equal(
    new URL(meta.find((m) => m.property === "og:url")?.content).href,
    new URL(absolute).href,
    `${path}: OG URL`,
  );
  const graphs = [
    ...body.matchAll(
      /<script\b[^>]*type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/g,
    ),
  ].map(([, json]) => JSON.parse(json));
  if (
    [
      "/",
      "/en",
      "/watch",
      "/en/watch",
      "/for-agents",
      "/en/for-agents",
    ].includes(path)
  )
    assert.ok(
      graphs.some((g) => g["@graph"]?.some((n) => n["@type"] === "WebPage")),
      `${path}: WebPage JSON-LD`,
    );
  assert.ok(body.includes(`lang="${path.startsWith("/en") ? "en" : "zh-CN"}"`));
  // Inspect actual markup, not embedded React payloads or structured data.
  const visible = decode(
    body
      .replace(/<script\b[^>]*>[\s\S]*?<\/script>/g, "")
      .replace(/<[^>]*>/g, " "),
  );
  if (["/", "/watch", "/en", "/en/watch"].includes(path) && unavailable) {
    assert.match(visible, /暂时无法加载|temporarily unavailable/);
    assert.doesNotMatch(visible, /还没有公开主题|No public topics yet/);
  }
  for (const graph of graphs.filter((g) => g["@type"] === "FAQPage")) {
    for (const question of graph.mainEntity) {
      assert.ok(visible.includes(question.name), `${path}: visible question`);
      assert.ok(
        visible.includes(question.acceptedAnswer.text),
        `${path}: visible answer`,
      );
    }
  }
  console.log(
    `PASS ${path}: SSR, metadata, language alternates and structured data`,
  );
}
const { body: robotHtml } = await read("/", { "User-Agent": "Googlebot" });
assert.ok(
  robotHtml.includes("AI Agent 的社区"),
  "Crawler receives page content",
);
const { body: sitemap } = await read("/sitemap.xml");
for (const path of pages)
  assert.ok(
    [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].some(
      ([, url]) => new URL(url).href === new URL(origin + path).href,
    ),
    `sitemap: ${path}`,
  );
assert.doesNotMatch(
  sitemap,
  /<loc>[^<]*\/(messages|hub|login|settings|api\/session)/,
);
const { body: robots } = await read("/robots.txt");
assert.match(robots, /User-Agent: \*[\s\S]*Allow: \/\n/);
assert.match(robots, /Disallow: \/messages/);
for (const path of ["/llms.txt", "/llms-full.txt"]) {
  const { response, body } = await read(path);
  assert.match(
    response.headers.get("content-type"),
    /text\/plain; charset=utf-8/,
  );
  assert.ok(body.includes(origin + "/en/for-agents"));
  assert.ok(body.includes(origin + "/en/watch"));
}
for (const path of [
  "/hub",
  "/en/hub",
  "/messages",
  "/en/messages",
  "/settings",
  "/en/settings",
]) {
  const privatePage = await fetch(base + path);
  assert.match(privatePage.headers.get("x-robots-tag"), /noindex/);
}
const { body: schema } = await read("/api/openapi.json");
assert.ok(
  Object.values(JSON.parse(schema).paths).every((p) =>
    Object.keys(p).every((m) => m === "get"),
  ),
);
console.log(
  `PASS discovery files, public-only sitemap and private noindex${unavailable ? "; API outage remains distinct from empty content" : ""}`,
);
