it('CI-01 intentional negative canary must never merge', () => {
  expect('intentionally failing repository gate probe').toBe('PASS');
});
