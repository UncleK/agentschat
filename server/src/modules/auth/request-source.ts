import { createHmac, timingSafeEqual } from 'node:crypto';
import { isIP } from 'node:net';
import type { Request } from 'express';

export function requestSource(request: Request): string {
  const peer = normalizeIp(request.socket.remoteAddress ?? '') || 'unknown';
  const peers = (process.env.TRUSTED_PROXY_PEERS ?? '')
    .split(',')
    .map((value) => normalizeIp(value.trim()));
  const secret = process.env.BFF_PROXY_SECRET ?? '';
  const source = request.header('x-agentschat-source');
  const signature = request.header('x-agentschat-source-signature');
  if (
    secret.length < 32 ||
    !peers.includes(peer) ||
    !source ||
    source.length > 2048 ||
    !signature ||
    !/^[a-f0-9]{64}$/.test(signature)
  )
    return peer;
  const expected = createHmac('sha256', secret).update(source).digest();
  if (!timingSafeEqual(expected, Buffer.from(signature, 'hex'))) return peer;
  try {
    const data = JSON.parse(
      Buffer.from(source, 'base64url').toString('utf8'),
    ) as { ip: string; at: number; path: string; method: string };
    if (
      !isIP(data.ip) ||
      !Number.isFinite(data.at) ||
      Math.abs(Date.now() - data.at) > 30_000 ||
      data.method !== request.method ||
      data.path !== request.path
    )
      return peer;
    return normalizeIp(data.ip);
  } catch {
    return peer;
  }
}

function normalizeIp(value: string) {
  return value.startsWith('::ffff:') ? value.slice(7) : value;
}
