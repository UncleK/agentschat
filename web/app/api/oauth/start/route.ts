import { createHash, randomBytes } from 'node:crypto';
import { NextRequest, NextResponse } from 'next/server';
import { acceptsOrigin, readSessionJson } from '@/lib/proxy-policy';
import { safeReturnPath } from '@/lib/auth-navigation';
import { sessionCookie } from '@/lib/config';
import { backend, noStore, oauthCookie, origin, secureCookie } from '@/lib/oauth-server';
export async function POST(request: NextRequest) {
  if (!acceptsOrigin('POST', request.headers.get('origin'), origin(request), request.headers.get('sec-fetch-site')))
    return noStore(NextResponse.json({ message: 'Cross-origin request rejected.' }, { status: 403 }));
  try {
    const input = await readSessionJson(request) as { provider?: string; link?: boolean; next?: string };
    if (!['google','github'].includes(input?.provider ?? '')) throw new Error('Unknown sign-in provider.');
    const verifier = randomBytes(32).toString('base64url');
    const token = request.cookies.get(sessionCookie)?.value;
    if (input.link && !token) return noStore(NextResponse.json({ message: 'Sign in before linking a provider.' }, { status: 401 }));
    const flow = await backend(`${input.provider}/${input.link ? 'link' : 'start'}`, {
      client: 'web', codeChallenge: createHash('sha256').update(verifier).digest('base64url'),
    }, input.link ? token : undefined);
    const target = new URL(flow.authorizationUrl);
    if (target.protocol !== 'https:' || !['accounts.google.com','github.com'].includes(target.hostname)) throw new Error('Invalid provider destination.');
    const response = noStore(NextResponse.json({ authorizationUrl: target.toString() }));
    response.cookies.set(oauthCookie, JSON.stringify({ flowId: flow.flowId, verifier, link: input.link === true,
      next: safeReturnPath(input.next) || '/hub' }), { httpOnly: true, secure: secureCookie, sameSite: 'lax', path: '/api/oauth', maxAge: 600 });
    return response;
  } catch (error) {
    return noStore(NextResponse.json({ message: error instanceof Error ? error.message : 'Unable to start sign-in.' }, { status: 400 }));
  }
}
