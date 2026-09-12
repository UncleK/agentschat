import { NextRequest, NextResponse } from "next/server";
import { apiOrigin, siteUrl, sessionCookie } from "@/lib/config";
import { acceptsOrigin, safeApiPath, requestOrigin } from "@/lib/proxy-policy";
export const dynamic = "force-dynamic";
async function proxy(
  request: NextRequest,
  context: { params: Promise<{ path: string[] }> },
) {
  const path = safeApiPath((await context.params).path);
  if (!path)
    return NextResponse.json({ message: "Invalid API path." }, { status: 400 });
  const isExternalClient =
    !request.headers.get("origin") &&
    !request.headers.get("sec-fetch-site") &&
    !request.cookies.has(sessionCookie);
  if (
    !isExternalClient &&
    !acceptsOrigin(
      request.method,
      request.headers.get("origin"),
      requestOrigin(
        request.headers.get("host"),
        request.nextUrl.origin,
        siteUrl,
      ),
      request.headers.get("sec-fetch-site"),
    )
  )
    return NextResponse.json(
      { message: "Cross-origin request rejected." },
      { status: 403 },
    );
  const headers = new Headers();
  for (const name of ["content-type", "accept", "range", "if-none-match"]) {
    const value = request.headers.get(name);
    if (value) headers.set(name, value);
  }
  const bearer = request.headers.get("authorization");
  const token = request.cookies.get(sessionCookie)?.value;
  if (bearer) headers.set("authorization", bearer);
  else if (token) headers.set("authorization", "Bearer " + token);
  try {
    const upstream = await fetch(
      apiOrigin + "/api/v1/" + path + request.nextUrl.search,
      {
        method: request.method,
        headers,
        redirect: "manual",
        cache: "no-store",
        body: ["GET", "HEAD"].includes(request.method)
          ? undefined
          : request.body,
        signal: AbortSignal.timeout(path.endsWith("/voice") ? 120000 : 30000),
        ...(!["GET", "HEAD"].includes(request.method)
          ? { duplex: "half" }
          : {}),
      } as RequestInit,
    );
    const responseHeaders = new Headers({
      "Cache-Control": "private, no-store",
      "X-Robots-Tag": "noindex, nofollow",
    });
    for (const name of [
      "content-type",
      "content-disposition",
      "content-range",
      "accept-ranges",
      "etag",
    ]) {
      const value = upstream.headers.get(name);
      if (value) responseHeaders.set(name, value);
    }
    // Fetch decodes compressed bodies; only an identity response retains its byte length.
    const encoding = upstream.headers.get("content-encoding");
    const length = upstream.headers.get("content-length");
    if (
      (!encoding || encoding === "identity") &&
      length &&
      /^\d+$/.test(length)
    ) {
      responseHeaders.set("content-length", length);
    }
    return new Response(upstream.body, {
      status: upstream.status,
      headers: responseHeaders,
    });
  } catch {
    return NextResponse.json(
      { message: "API is unavailable. Please try again." },
      { status: 503 },
    );
  }
}
export {
  proxy as GET,
  proxy as POST,
  proxy as PATCH,
  proxy as PUT,
  proxy as DELETE,
  proxy as HEAD,
};
