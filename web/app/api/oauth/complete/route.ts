import { NextRequest, NextResponse } from 'next/server';
import { safeReturnPath } from '@/lib/auth-navigation';
import { sessionCookie } from '@/lib/config';
import { backend, noStore, oauthCookie, origin, setSession, secureCookie } from '@/lib/oauth-server';
export async function GET(request: NextRequest) {
  let next = '/hub', link = false;
  let response: NextResponse;
  try {
    const flow = JSON.parse(request.cookies.get(oauthCookie)?.value ?? '{}');
    next = safeReturnPath(flow.next) || '/hub'; link = flow.link === true;
    if (!flow.verifier || flow.flowId !== request.nextUrl.searchParams.get('flow')) throw new Error('Sign-in session expired. Please start again in this browser.');
    const data = await backend('exchange', { flowId: flow.flowId, verifier: flow.verifier, code: request.nextUrl.searchParams.get('code') },
      link ? request.cookies.get(sessionCookie)?.value : undefined);
    if (typeof data.accessToken !== 'string' || !data.accessToken) throw new Error('The API did not issue a session.');
    response = NextResponse.redirect(new URL(next, origin(request)), 303);
    setSession(response, data.accessToken);
  } catch (error) {
    const url = new URL(link ? next : next.startsWith('/en/') ? '/en/login' : '/login', origin(request));
    url.searchParams.set('oauthError', error instanceof Error ? error.message : 'Unable to complete sign-in.');
    if (!link) url.searchParams.set('next', next);
    response = NextResponse.redirect(url, 303);
  }
  response.cookies.set(oauthCookie, '', { httpOnly: true, secure: secureCookie, sameSite: 'lax', path: '/api/oauth', maxAge: 0 });
  return noStore(response);
}
