import { NextRequest, NextResponse } from "next/server";
import { basePath, localePath, LOCALE_COOKIE } from "./lib/locale";
import { avatarCachePolicy, AVATAR_CACHE_COOKIE, AVATAR_CACHE_VERSION } from './lib/avatar-cache-policy';
export function proxy(request: NextRequest) {
  const path = request.nextUrl.pathname;
  const base = basePath(path);
  if (base.endsWith("/transcript")) return NextResponse.next();
  if (
    base !== "/" &&
    !/^\/(agents|forum|live|hub|messages|notifications|settings|connections|login|register|docs|guide|privacy|for-agents|watch|app|discussions|rooms)(\/|$)/.test(
      base,
    )
  )
    return NextResponse.next();
  const english = path === "/en" || path.startsWith("/en/");
  const locale = english ? "en" : "zh";
  if (!english && request.cookies.get(LOCALE_COOKIE)?.value === "en") {
    const url = request.nextUrl.clone();
    url.pathname = localePath(path, "en");
    return NextResponse.redirect(url);
  }
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-agents-chat-locale", locale);
  const response = NextResponse.next({ request: { headers: requestHeaders } });
  const cacheReset = avatarCachePolicy(request.cookies.get(AVATAR_CACHE_COOKIE)?.value, request.headers.get('sec-fetch-dest'));
  if (cacheReset) {
    response.headers.set('Clear-Site-Data', cacheReset);
    response.cookies.set(AVATAR_CACHE_COOKIE, AVATAR_CACHE_VERSION, {
      path: '/', maxAge: 31536000, sameSite: 'lax', httpOnly: true,
      secure: request.nextUrl.protocol === 'https:',
    });
  }
  response.cookies.set(LOCALE_COOKIE, locale, {
    path: "/",
    maxAge: 31536000,
    sameSite: "lax",
    secure: request.nextUrl.protocol === "https:",
  });
  if (
    /^\/(hub|messages|notifications|settings|connections|login|register|app|discussions|rooms)(\/|$)/.test(
      base,
    )
  )
    response.headers.set("X-Robots-Tag", "noindex, nofollow");
  return response;
}
export const config = { matcher: ["/((?!api|_next|.*\\..*).*)"] };
