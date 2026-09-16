import { lookup } from 'node:dns/promises';
import { request } from 'node:https';
import { isIP } from 'node:net';
import ipaddr from 'ipaddr.js';
import { FederationHttpException } from './federation.errors';

export function isPublicAddress(address: string): boolean {
  if (!ipaddr.isValid(address)) return false;
  const parsed = ipaddr.process(address);
  if (parsed.range() !== 'unicast') return false;
  if (parsed.kind() === 'ipv6') {
    // Global unicast only. Block transition/special-use allocations as well.
    const v6 = parsed as ipaddr.IPv6;
    if (!v6.match(ipaddr.IPv6.parse('2000::'), 3)) return false;
    for (const subnet of [
      '2001::/23',
      '2001:db8::/32',
      '2002::/16',
      '3fff::/20',
    ]) {
      if (v6.match(ipaddr.IPv6.parseCIDR(subnet))) return false;
    }
  }
  return true;
}

export function validateWebhookUrl(value: string): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw blocked();
  }
  const host = url.hostname.replace(/^\[|\]$/g, '');
  if (
    url.protocol !== 'https:' ||
    url.username ||
    url.password ||
    url.hash ||
    (url.port && url.port !== '443') ||
    host === 'localhost' ||
    host.endsWith('.localhost') ||
    (isIP(host) && !isPublicAddress(host))
  )
    throw blocked();
  return url;
}

function blocked() {
  return new FederationHttpException(
    400,
    'unsafe_webhook_destination',
    'Webhook requires a public HTTPS destination on port 443, without credentials or redirects. Polling remains available.',
  );
}

// No proxy env, redirects or global pooled agent. Resolve once, pin exactly that
// approved address, retain hostname for TLS/SNI, and verify the connected peer
// before sending the signed payload. Test seams are module mocks, not env flags.
export async function postWebhook(
  value: string,
  body: string,
  headers: Record<string, string>,
  signal: AbortSignal,
): Promise<{ ok: boolean; status: number }> {
  const url = validateWebhookUrl(value);
  const hostname = url.hostname.replace(/^\[|\]$/g, '');
  const addresses = isIP(hostname)
    ? [{ address: hostname, family: isIP(hostname) }]
    : await Promise.race([
        lookup(hostname, { all: true, verbatim: true }),
        new Promise<never>((_, reject) => {
          if (signal.aborted) reject(new Error('Webhook timeout.'));
          else
            signal.addEventListener(
              'abort',
              () => reject(new Error('Webhook timeout.')),
              { once: true },
            );
        }),
      ]);
  if (
    !addresses.length ||
    addresses.some((item) => !isPublicAddress(item.address))
  )
    throw blocked();
  const selected = addresses[0];
  return new Promise((resolve, reject) => {
    const req = request(
      url,
      {
        method: 'POST',
        agent: false,
        // Pin the address family as well: Node's auto-family lookup otherwise
        // requests an array of answers from custom lookup callbacks.
        family: selected.family,
        signal,
        headers: {
          ...headers,
          'content-length': String(Buffer.byteLength(body)),
        },
        lookup: (_host, _options, callback) =>
          callback(null, selected.address, selected.family),
      },
      (response) => {
        const status = response.statusCode ?? 0;
        response.destroy();
        resolve({ ok: status >= 200 && status < 300, status });
      },
    );
    req.once('error', reject);
    req.once('socket', (socket) => {
      socket.once('secureConnect', () => {
        const actual = socket.remoteAddress;
        if (
          !actual ||
          !isPublicAddress(actual) ||
          ipaddr.process(actual).toString() !==
            ipaddr.process(selected.address).toString()
        ) {
          req.destroy(
            new Error(
              'Webhook connected peer differs from the approved address.',
            ),
          );
          return;
        }
        req.end(body);
      });
    });
  });
}
