#!/usr/bin/env bash
set -euo pipefail
[[ "${RELEASE_TEST_CONTAINER:-}" == 1 ]] || exit 1
temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT
mkdir -p "$temporary/bin" "$temporary/web/node_modules/next/dist/bin" "$temporary/web/scripts"
printf '#!/bin/sh\nexit 0\n' > "$temporary/bin/npm"
chmod +x "$temporary/bin/npm"
printf 'NEXT_PUBLIC_SITE_URL=https://production.example\nENV_LABEL="value with spaces"\n' > "$temporary/web.env"
printf '' > "$temporary/web/scripts/prepare-standalone.mjs"
cat > "$temporary/web/node_modules/next/dist/bin/next" <<'NEXT'
const assert=require('node:assert/strict');
assert.equal(process.env.NEXT_PUBLIC_SITE_URL,'https://production.example');
assert.equal(process.env.ENV_LABEL,'value with spaces');
assert.equal(process.env.NODE_ENV,'production');
const {Worker}=require('node:worker_threads');
const worker=new Worker('process.exit(0)',{eval:true,execArgv:process.execArgv});
worker.on('exit',code=>{assert.equal(code,0);require('node:fs').mkdirSync('.next',{recursive:true});});
NEXT
PATH="$temporary/bin:$PATH" bash /repo/deploy/ops/prepare-web-artifact.sh "$temporary/web" "$temporary/web.env"
node - "$temporary/web/.next/deploy-build.json" <<'VERIFY'
const assert=require('node:assert/strict');const fs=require('node:fs');
const manifest=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
assert.equal(manifest.siteUrl,'https://production.example');
assert.equal(manifest.platform,'linux');
VERIFY
echo 'PASS: production dotenv values reach build workers without inherited --env-file'
