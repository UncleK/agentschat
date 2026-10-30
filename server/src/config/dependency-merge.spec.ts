import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';

it('verifies the installed CLI dependency blocks returned-object prototype poisoning', () => {
  expect(() =>
    execFileSync(process.execPath, [
      resolve(__dirname, '../../scripts/verify-security-patches.cjs'),
    ]),
  ).not.toThrow();
});
