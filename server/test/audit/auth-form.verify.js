async (page) => {
  // Exercise the server-rendered form before any client event handler exists.
  const blockScripts = route => route.request().resourceType() === 'script'
    ? route.abort() : route.continue();
  await page.route('**/*', blockScripts);
  try {
    for (const path of ['/login', '/register']) {
      await page.goto('http://127.0.0.1:18100' + path, { waitUntil: 'domcontentloaded' });
      const form = page.locator('form.ws-form');
      if (await form.getAttribute('method') !== 'post')
        throw new Error(path + ': unhydrated credentials can enter the URL');
      const fields = form.locator('input, button');
      for (let i = 0; i < await fields.count(); i++) {
        if (!await fields.nth(i).isDisabled())
          throw new Error(path + ': form accepts input before its handler is ready');
      }
    }
    return { result: 'passed', loginAndRegistration: true, scriptsBlocked: true, credentialsCannotSubmitBeforeHydration: true };
  } finally {
    await page.unroute('**/*', blockScripts);
  }
}
