import { createHmac, timingSafeEqual } from 'node:crypto';
import { isIP } from 'node:net';

// Caddy replaces both headers; direct requests to Next cannot mint a source
// assertion without the edge secret. The API separately checks the BFF peer.
export function trustedSourceHeaders(incoming: Headers, method: string, path: string): Record<string, string> {
  const edgeSecret = process.env.EDGE_TO_WEB_SECRET ?? '';
  const apiSecret = process.env.BFF_PROXY_SECRET ?? '';
  const supplied = incoming.get('x-agentschat-edge-key') ?? '';
  const ip = incoming.get('x-agentschat-client-ip') ?? '';
  if (edgeSecret.length < 32 || apiSecret.length < 32 || Buffer.byteLength(supplied) !== Buffer.byteLength(edgeSecret) ||
      !timingSafeEqual(Buffer.from(supplied), Buffer.from(edgeSecret)) || !isIP(ip)) return {};
  const source = Buffer.from(JSON.stringify({ ip, method, path, at: Date.now() })).toString('base64url');
  return { 'x-agentschat-source': source, 'x-agentschat-source-signature': createHmac('sha256', apiSecret).update(source).digest('hex') };
}
