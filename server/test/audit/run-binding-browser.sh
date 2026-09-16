#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
mkdir -p output/reaudit
export DATABASE_URL="${DATABASE_URL:-postgres://agents_chat:agents_chat@127.0.0.1:5432/agents_chat}"
export MINIO_PORT="${MINIO_PORT:-9000}"
export API_ORIGIN=http://127.0.0.1:18080
export NEXT_PUBLIC_SITE_URL=http://127.0.0.1:18100
export SESSION_COOKIE_SECURE=false
export NO_PROXY=localhost,127.0.0.1,::1
export PYTHONDONTWRITEBYTECODE=1
fixture_pid= web_pid= pty_pid=
cleanup() {
  npx --yes --package @playwright/cli@0.1.20 playwright-cli -s=reaudit-ci close >/dev/null 2>&1 || true
  curl --noproxy '*' --silent --fail -X POST http://127.0.0.1:18081/stop >/dev/null || true
  for child in "$pty_pid" "$web_pid" "$fixture_pid"; do
    if [[ -n "$child" ]]; then kill "$child" 2>/dev/null || true; fi
  done
}
trap cleanup EXIT
node server/test/audit/reaudit-fixture.cjs >output/reaudit/fixture.log 2>&1 & fixture_pid=$!
for attempt in $(seq 1 60); do
  if curl --noproxy '*' --silent --fail http://127.0.0.1:18081/status >/dev/null; then break; fi
  sleep 1
done
curl --noproxy '*' --silent --fail http://127.0.0.1:18081/status >/dev/null
npm --prefix web ci
npm --prefix web run build >output/reaudit/web-build.log 2>&1
(cd web && exec node node_modules/next/dist/bin/next start --hostname 127.0.0.1 --port 18100) >output/reaudit/web.log 2>&1 & web_pid=$!
for attempt in $(seq 1 60); do
  if curl --noproxy '*' --silent --fail http://127.0.0.1:18100/api/session?status=1 >/dev/null; then break; fi
  sleep 1
done
python skills/agents-chat-v1/adapter/launch.py --server-base-url http://127.0.0.1:18100 --mode public --slot rr12 --state-dir output/reaudit/python --handle reaudit-ci-python --display-name 'Synthetic CI Agent' --skip-poll
python skills/agents-chat-v1/adapter/launch.py --server-base-url http://127.0.0.1:18100 --mode public --slot rr12 --state-dir output/reaudit/python --skip-poll --submit-action-json '{"type":"forum.topic.create","payload":{"title":"Python before registration","content":"Synthetic history before human registration"}}' --wait-action
curl --noproxy '*' --silent --fail -X POST http://127.0.0.1:18081/prepare >/dev/null
npx --yes --package @playwright/cli@0.1.20 playwright-cli install-browser chrome
python server/test/audit/adapter-pty-driver.py >output/reaudit/pty-result.json & pty_pid=$!
npx --yes --package @playwright/cli@0.1.20 playwright-cli -s=reaudit-ci open http://127.0.0.1:18100/login
npx --yes --package @playwright/cli@0.1.20 playwright-cli -s=reaudit-ci run-code --filename server/test/audit/binding-browser.verify.js | tee output/reaudit/browser-result.txt
grep -Eq '"result"[[:space:]]*:[[:space:]]*"passed"' output/reaudit/browser-result.txt
wait "$pty_pid"
grep -Eq '"result"[[:space:]]*:[[:space:]]*"passed"' output/reaudit/pty-result.json
