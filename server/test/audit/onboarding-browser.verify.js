async (page) => {
  // Separate browser context: no human session, no changes to the binding fixture.
  const base = 'http://127.0.0.1:18100';
  const context = await page.context().browser().newContext();
  const browserPage = await context.newPage();
  const errors = [];
  browserPage.on('pageerror', error => errors.push(error.message));
  await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: base });
  const checked = [];
  try {
    for (const width of [1440, 390]) {
      await browserPage.setViewportSize({ width, height: 1000 });
      for (const path of ['/for-agents', '/en/for-agents', '/docs', '/en/docs']) {
        // Explicit language URLs, not a previous visit's language preference.
        await context.clearCookies();
        await browserPage.goto(base + path, { waitUntil: 'networkidle' });
        const invitation = browserPage.locator('.agent-invitation');
        await invitation.waitFor();
        const text = await invitation.locator('textarea').inputValue();
        if (!text.includes(base + '/join.md')) throw new Error('Wrong invitation origin: ' + path);
        const en = path.startsWith('/en');
        const button = invitation.getByRole('button', { name: en ? 'Copy invitation' : '复制邀请', exact: true });
        await button.click();
        await invitation.getByRole('button', { name: en ? 'Copied — send it to your agent' : '已复制，发给你的 Agent', exact: true }).waitFor();
        const copied = await browserPage.evaluate(() => navigator.clipboard.readText());
        if (copied !== text) throw new Error('Clipboard differs from visible invitation: ' + path);
        const overflow = await browserPage.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1);
        if (overflow) throw new Error('Horizontal overflow: ' + path + ' at ' + width);
        if (await browserPage.locator('[data-nextjs-dialog]').count()) throw new Error('Next.js error overlay');
        if (path === '/en/for-agents') {
          await invitation.screenshot({ path: 'output/reaudit/onboarding-' + width + '.png' });
        }
        checked.push({ path, width, copied: true, overflow: false });
      }
    }
    // Clipboard rejection must not claim success and must provide manual selection.
    await browserPage.reload({ waitUntil: 'networkidle' });
    await browserPage.evaluate(() => {
      Object.defineProperty(navigator.clipboard, 'writeText', { configurable: true, value: async () => { throw new Error('Synthetic clipboard rejection'); } });
    });
    await browserPage.getByRole('button', { name: 'Copy invitation', exact: true }).click();
    await browserPage.getByRole('status').filter({ hasText: 'Copy failed.' }).waitFor();
    const selected = await browserPage.locator('.agent-invitation textarea').evaluate(el => el.selectionStart === 0 && el.selectionEnd === el.value.length && document.activeElement === el);
    if (!selected) throw new Error('Manual copy fallback did not select the invitation');
    await context.clearCookies();
    await browserPage.goto(base, { waitUntil: 'networkidle' });
    await browserPage.getByRole('button', { name: '邀请 Agent 加入', exact: true }).click();
    await browserPage.getByRole('dialog').locator('.agent-invitation textarea').waitFor();
    if (errors.length) throw new Error(errors.join('\n'));
    return { result: 'passed', checked, clipboardFailure: 'manual-selection', humanLoginRequired: false, homepageDialog: true };
  } finally {
    await context.close();
  }
}
