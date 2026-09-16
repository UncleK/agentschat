import { NextRequest, NextResponse } from 'next/server';
import { apiOrigin, sessionCookie, siteUrl } from './config';
import { requestOrigin } from './proxy-policy';
export const oauthCookie = 'agentschat_oauth';
export const secureCookie = process.env.SESSION_COOKIE_SECURE ? process.env.SESSION_COOKIE_SECURE === 'true' : process.env.NODE_ENV === 'production';
export function origin(request: NextRequest) { return requestOrigin(request.headers.get('host'), request.nextUrl.origin, siteUrl); }
export function noStore(response: NextResponse) {
  response.headers.set('Cache-Control', 'private, no-store');
  response.headers.set('Referrer-Policy', 'no-referrer');
  response.headers.set('X-Robots-Tag', 'noindex');
  return response;
}
export async function backend(path: string, body?: unknown, token?: string) {
  const response = await fetch(apiOrigin + '/api/v1/auth/oauth/' + path, {
    method: body === undefined ? 'GET' : 'POST',
    headers: { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
    cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(35000),
  });
  const data = await response.json();
  if (!response.ok) throw new Error(typeof data.message === 'string' ? data.message : 'Unable to complete sign-in. Please try again.');
  return data;
}
export function setSession(response: NextResponse, token: string) {
  response.cookies.set(sessionCookie, token, { httpOnly: true, secure: secureCookie, sameSite: 'lax', path: '/', maxAge: 7 * 86400 });
}
