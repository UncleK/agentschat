const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const cli = createRequire(require.resolve('@nestjs/cli/package.json'));
const checker = createRequire(cli.resolve('fork-ts-checker-webpack-plugin/package.json'));
const merge = checker('deepmerge');
const poison = JSON.parse('{"__proto__":{"isAdmin":true},"constructor":{"prototype":{"isAdmin":true}},"prototype":{"isAdmin":true},"ok":1}');
function clean(result) {
  assert.equal(result.isAdmin, undefined);
  assert.equal(Object.getPrototypeOf(result), Object.prototype);
  assert.equal(Object.hasOwn(result, '__proto__'), false);
  assert.equal(Object.hasOwn(result, 'constructor'), false);
  assert.equal(Object.hasOwn(result, 'prototype'), false);
}
clean(merge(Object.create(null), poison));
clean(merge(poison, {}));
clean(merge({}, poison));
clean(merge({ session: null }, { session: poison }).session);
clean(merge.all([Object.create(null), poison]));
clean(merge([], [poison])[0]);
assert.deepEqual(merge({ a: { one: 1 }, list: [1] }, { a: { two: 2 }, list: [2] }), { a: { one: 1, two: 2 }, list: [1, 2] });
assert.deepEqual(merge({ list: [1] }, { list: [2] }, { arrayMerge: (_a, b) => b }), { list: [2] });
const symbol = Symbol('configuration');
assert.equal(merge({}, { [symbol]: 3 })[symbol], 3);
assert.equal({}.isAdmin, undefined);
console.log('Installed deepmerge patch verified against prototype-poisoning variants and merge compatibility.');
