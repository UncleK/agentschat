import { NextRequest, NextResponse } from "next/server";
import { apiOrigin, siteUrl, sessionCookie } from "@/lib/config";
import {
  acceptsOrigin,
  requestOrigin,
  readSessionJson,
  PayloadTooLarge,
} from "@/lib/proxy-policy";
export const dynamic = "force-dynamic";
const secure = process.env.SESSION_COOKIE_SECURE
  ? process.env.SESSION_COOKIE_SECURE === "true"
  : process.env.NODE_ENV === "production";
function response(body: unknown, status = 200) {
  return NextResponse.json(body, {
    status,
    headers: {
      "Cache-Control": "private, no-store",
      "X-Robots-Tag": "noindex",
    },
  });
}
export async function GET(request: NextRequest) {
  const statusOnly = request.nextUrl.searchParams.get("status") === "1";
  const token = request.cookies.get(sessionCookie)?.value;
  if (!token)
    return statusOnly
      ? response({ authenticated: false })
      : response({ message: "Sign in to continue." }, 401);
  try {
    const upstream = await fetch(apiOrigin + "/api/v1/auth/me", {
      headers: { authorization: "Bearer " + token },
      cache: "no-store",
      signal: AbortSignal.timeout(10000),
    });
    const data = await upstream.json();
    const result =
      statusOnly && (upstream.ok || upstream.status === 401)
        ? response({ authenticated: upstream.ok })
        : response(data, upstream.status);
    if (upstream.status === 401) result.cookies.delete(sessionCookie);
    return result;
  } catch {
    return response({ message: "Unable to connect to your account." }, 503);
  }
}
export async function POST(request: NextRequest) {
  if (
    !acceptsOrigin(
      "POST",
      request.headers.get("origin"),
      requestOrigin(
        request.headers.get("host"),
        request.nextUrl.origin,
        siteUrl,
      ),
      request.headers.get("sec-fetch-site"),
    )
  )
    return response({ message: "Cross-origin request rejected." }, 403);
  let input: Record<string, unknown>;
  try {
    input = (await readSessionJson(request)) as Record<string, unknown>;
  } catch (error) {
    if (error instanceof PayloadTooLarge)
      return response({ message: "Session request is too large." }, 413);
    return response({ message: "Invalid JSON." }, 400);
  }
  if (!input || typeof input !== "object" || Array.isArray(input))
    return response({ message: "Invalid JSON object." }, 400);
  if (input.action === "logout") {
    const result = response({ message: "Signed out." });
    result.cookies.delete(sessionCookie);
    return result;
  }
  if (!["login", "register"].includes(String(input.action)))
    return response({ message: "Invalid session action." }, 400);
  const payload =
    input.action === "login"
      ? { email: input.email, password: input.password }
      : {
          email: input.email,
          password: input.password,
          username: input.username,
          displayName: input.displayName,
        };
  try {
    const upstream = await fetch(
      apiOrigin +
        "/api/v1/auth/" +
        (input.action === "login" ? "login/email" : "register/email"),
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(payload),
        cache: "no-store",
        signal: AbortSignal.timeout(20000),
      },
    );
    const data = await upstream.json();
    if (!upstream.ok) {
      const result = response(data, upstream.status);
      const retry = upstream.headers.get("retry-after");
      if (retry) result.headers.set("Retry-After", retry);
      return result;
    }
    const token = data.accessToken ?? data.session?.accessToken;
    if (typeof token !== "string")
      return response({ message: "The API did not issue a session." }, 502);
    const { accessToken: _, ...publicData } = data;
    if (publicData.session) {
      const { accessToken: __, ...session } = publicData.session;
      publicData.session = session;
    }
    const result = response(publicData, upstream.status);
    result.cookies.set(sessionCookie, token, {
      httpOnly: true,
      secure,
      sameSite: "lax",
      path: "/",
      maxAge: 7 * 24 * 60 * 60,
    });
    return result;
  } catch {
    return response({ message: "Unable to connect. Please try again." }, 503);
  }
}
