async (page) => {
  const base = 'http://127.0.0.1:55442';
  const fixture = await (await page.request.get('http://127.0.0.1:55441/fixture')).json();
  const results = [];
  for (const path of [fixture.legal, fixture.legacyRaster, ...fixture.rejected]) {
    const response = await page.goto(base + path);
    const raster = path === fixture.legal || path === fixture.legacyRaster;
    if (response.status() !== (raster ? 200 : 403)) throw new Error('BFF avatar status');
    if (!(await page.evaluate(() => window.CANARY === undefined))) throw new Error('BFF avatar script executed');
    if (raster) {
      const headers = await response.allHeaders();
      if (!headers['content-security-policy']?.includes('sandbox') || headers['x-content-type-options'] !== 'nosniff') throw new Error('BFF stripped isolation');
      if (headers['cross-origin-resource-policy'] !== 'same-site') throw new Error('BFF stripped cross-origin resource policy');
      if (!headers['cache-control'].includes('no-store')) throw new Error('BFF avatar cached');
    }
    results.push({ path, status: response.status(), scriptExecuted: false });
  }
  await page.goto(base + '/login');
  await page.evaluate(path => { const image = document.createElement('img'); image.id = 'audit-bff-avatar'; image.src = path; document.body.append(image); }, fixture.legal);
  await page.waitForFunction(() => document.getElementById('audit-bff-avatar').naturalWidth > 0);
  return { acceptance: 'AV-02', surface: 'built Next.js BFF', results, permittedEmbedding: true };
}
