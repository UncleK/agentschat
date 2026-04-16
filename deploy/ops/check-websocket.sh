#!/usr/bin/env bash
set -euo pipefail

TARGET_URL="${1:-${WS_CHECK_URL:-ws://127.0.0.1:3000/ws}}"
TOKEN="${WS_CHECK_TOKEN:-}"
EXPECTED_STATUS="${WS_EXPECTED_STATUS:-}"
CONNECT_HOST="${WS_CHECK_CONNECT_HOST:-}"
CONNECT_PORT="${WS_CHECK_CONNECT_PORT:-}"
HOST_HEADER="${WS_CHECK_HOST_HEADER:-}"

if [[ -z "$EXPECTED_STATUS" ]]; then
  if [[ -n "$TOKEN" ]]; then
    EXPECTED_STATUS="101"
  else
    EXPECTED_STATUS="401"
  fi
fi

node - "$TARGET_URL" "$TOKEN" "$EXPECTED_STATUS" "$CONNECT_HOST" "$CONNECT_PORT" "$HOST_HEADER" <<'NODE'
const crypto = require('node:crypto');
const net = require('node:net');
const tls = require('node:tls');

const [, , rawUrl, token, expectedStatusRaw, connectHostRaw, connectPortRaw, hostHeaderRaw] = process.argv;
const expectedStatus = Number.parseInt(expectedStatusRaw, 10);
const target = new URL(rawUrl);
const isSecure = target.protocol === 'wss:';
const defaultPort = isSecure ? 443 : 80;
const port = Number(connectPortRaw || target.port || defaultPort);
const connectHost = connectHostRaw || target.hostname;
const hostHeader = hostHeaderRaw || `${target.hostname}${target.port ? `:${target.port}` : ''}`;

if (token) {
  target.searchParams.set('access_token', token);
}

const path = `${target.pathname}${target.search}`;
const websocketKey = crypto.randomBytes(16).toString('base64');
const headers = [
  `GET ${path} HTTP/1.1`,
  `Host: ${hostHeader}`,
  'Upgrade: websocket',
  'Connection: Upgrade',
  `Sec-WebSocket-Key: ${websocketKey}`,
  'Sec-WebSocket-Version: 13',
  '',
  '',
].join('\r\n');

const transport = isSecure
  ? tls.connect({
      host: connectHost,
      port,
      servername: hostHeaderRaw || target.hostname,
    })
  : net.connect({
      host: connectHost,
      port,
    });

let response = '';

transport.setTimeout(10000, () => {
  console.error('WebSocket check timed out.');
  transport.destroy();
  process.exit(1);
});

transport.on('connect', () => {
  transport.write(headers);
});

transport.on('data', (chunk) => {
  response += chunk.toString('utf8');
  if (!response.includes('\r\n\r\n')) {
    return;
  }

  const firstLine = response.split('\r\n', 1)[0] ?? '';
  const match = firstLine.match(/^HTTP\/1\.1\s+(\d{3})/);
  const actualStatus = match ? Number.parseInt(match[1], 10) : NaN;

  if (actualStatus !== expectedStatus) {
    console.error(`Unexpected WebSocket status: expected ${expectedStatus}, got ${firstLine}`);
    transport.destroy();
    process.exit(1);
  }

  console.log(`WebSocket route check passed with status ${actualStatus}.`);
  transport.destroy();
  process.exit(0);
});

transport.on('error', (error) => {
  console.error(`WebSocket check failed: ${error.message}`);
  process.exit(1);
});
NODE
