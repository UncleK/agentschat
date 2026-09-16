async (page) => {
  const base = 'http://127.0.0.1:55441';
  const check = (condition, message) => { if (!condition) throw new Error(message); };
  const fixture = await (await page.request.get(base + '/fixture')).json();
  const before = (await (await page.request.get(base + '/canary-status')).json()).canaryHits;
  // Positive control proves this browser detects actual script execution.
  await page.goto(base + '/control.svg');
  await page.waitForFunction(() => window.CANARY === 'executed');
  await page.waitForFunction(async (count) => (await (await fetch('/canary-status')).json()).canaryHits === count, before + 1);
  const results = [];
  for (const path of [fixture.legal, fixture.legacyRaster, ...fixture.rejected]) {
    const response = await page.goto(base + path);
    const isRaster = path === fixture.legal || path === fixture.legacyRaster;
    check(response.status() === (isRaster ? 200 : 403), 'Unexpected avatar status');
    check(await page.evaluate(() => window.CANARY === undefined), 'Avatar executed the script canary');
    if (isRaster) {
      const headers = response.headers();
      check(headers['content-type'].startsWith('image/png'), 'Output must be re-encoded PNG');
      check(headers['x-content-type-options'] === 'nosniff', 'Missing no-sniff');
      check(headers['content-security-policy'].includes('sandbox'), 'Missing sandbox');
      check(headers['cache-control'] === 'no-store', 'Avatar must not be cached');
      check(!(await response.body()).toString().includes('<script>'), 'Trailing active content survived re-encoding');
    }
    results.push({ path, status: response.status(), scriptExecuted: false });
  }
  await page.goto(base + '/harness');
  await page.waitForFunction(() => [...document.images].every(img => img.complete && img.naturalWidth > 0));
  const hits = await (await page.request.get(base + '/canary-status')).json();
  check(hits.canaryHits === before + 1, 'An avatar sent a script canary request');
  return { acceptance: 'AV-02', browser: 'Chromium', controlExecuted: true, avatarCanaryHits: hits.canaryHits - before - 1, directNavigation: results, legalAndLegacyImgEmbed: true };
}
