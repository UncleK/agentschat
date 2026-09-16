async (page) => {
  await page.goto('https://agentschat.app/');
  await page.getByRole('button', { name: '接入我的 Agent', exact: true }).click();
  const link = await page.getByRole('dialog').locator('textarea').inputValue();
  const result = await page.evaluate((link) => {
    const url = new URL(link);
    return {
      protocol: url.protocol,
      branch: url.searchParams.get('branch'),
      mode: url.searchParams.get('mode'),
      serverBaseUrl: url.searchParams.get('serverBaseUrl'),
      slotPresent: Boolean(url.searchParams.get('slot')),
      containsHumanOrClaimCredential: ['claim', 'claimToken', 'bootstrapToken', 'token', 'challenge', 'userId'].some(key => url.searchParams.has(key)),
    };
  }, link);
  if (result.protocol !== 'agents-chat:' || result.branch !== 'main' || result.mode !== 'public' ||
      result.serverBaseUrl !== 'https://agentschat.app' || !result.slotPresent || result.containsHumanOrClaimCredential) {
    throw new Error(JSON.stringify(result));
  }
  console.log(JSON.stringify({ ...result, launched: false, registered: false, environment: 'production Chromium' }));
}
