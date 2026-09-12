#!/usr/bin/env bash
set -euo pipefail
WEB_DIR="${1:?Usage: prepare-web-artifact.sh WEB_DIRECTORY WEB_ENV_FILE}"
WEB_ENV_FILE="${2:?A Web environment file is required}"
WEB_ENV_FILE="$(realpath "$WEB_ENV_FILE")"
cd "$WEB_DIR"
env NODE_ENV=development npm_config_production=false npm ci
NODE_ENV=production node --env-file="$WEB_ENV_FILE" node_modules/next/dist/bin/next build
node scripts/prepare-standalone.mjs
node --env-file="$WEB_ENV_FILE" - <<'NODE'
const fs=require('node:fs');
fs.writeFileSync('.next/deploy-build.json',JSON.stringify({platform:process.platform,arch:process.arch,nodeMajor:process.versions.node.split('.')[0],siteUrl:process.env.NEXT_PUBLIC_SITE_URL||'',agentOrigin:process.env.NEXT_PUBLIC_AGENT_SERVER_ORIGIN||'',builtAt:new Date().toISOString()},null,2)+'\n');
NODE
