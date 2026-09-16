async (page) => {
  const base = 'http://127.0.0.1:55443';
  const check = (condition, message) => { if (!condition) throw new Error(message); };
  await page.context().clearCookies();
  const session = await page.context().newCDPSession(page);
  await session.send('Network.clearBrowserCache');
  await session.detach();
  await page.request.post(base + '/fixture-reset');
  await page.goto(base + '/cached-avatar.svg');
  await page.waitForFunction(() => window.OLD_AVATAR_EXECUTED === true);
  await page.goto(base + '/blank');
  await page.evaluate(() => { document.cookie = 'synthetic-session=retain;path=/'; localStorage.setItem('synthetic-identity', 'retain'); });
  await page.request.post(base + '/fixture-fix');
  await page.goto(base + '/cached-avatar.svg');
  await page.waitForFunction(() => window.OLD_AVATAR_EXECUTED === true);
  check((await (await page.request.get(base + '/fixture-state')).json()).reads === 1, 'Precondition: legacy response must really be cached');
  const document = await page.goto(base + '/login');
  check((await document.allHeaders())['clear-site-data'] === '"cache"', 'First document must clear HTTP cache only: ' + JSON.stringify(await document.allHeaders()));
  const media = await page.goto(base + '/cached-avatar.svg');
  check(media.headers()['content-type'] === 'image/png', 'Legacy browser cache was reused');
  check(await page.evaluate(() => window.OLD_AVATAR_EXECUTED === undefined), 'Cached active avatar executed after reset');
  check((await (await page.request.get(base + '/fixture-state')).json()).reads === 2, 'Must re-read avatar from protected origin');
  const next = await page.goto(base + '/login');
  check(!(await next.allHeaders())['clear-site-data'], 'Cache should clear only once');
  check(await page.evaluate(() => document.cookie.includes('synthetic-session=retain') && localStorage.getItem('synthetic-identity') === 'retain'), 'Cache migration erased session or identity');
  return { acceptance: 'AV-03', realBrowserCacheSeeded: true, legacyCacheInvalidated: true, protectedMediaRead: true, oldScriptAfterReset: false, sessionAndIdentityRetained: true, resetOnce: true };
}
