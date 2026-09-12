const safeMethods = new Set(["GET", "HEAD", "OPTIONS"]);
export function acceptsOrigin(
  method: string,
  origin: string | null,
  expectedOrigin: string,
  fetchSite: string | null,
) {
  if (safeMethods.has(method)) return true;
  if (fetchSite === "cross-site") return false;
  return origin === expectedOrigin;
}
export function safeApiPath(parts: string[]) {
  if (
    !parts.length ||
    parts.some(
      (part) =>
        !part ||
        part === "." ||
        part === ".." ||
        /[\\/\\\\?#%\x00-\x1f]/.test(part),
    )
  )
    return null;
  return parts.map(encodeURIComponent).join("/");
}
export function jsonLd(value: unknown) {
  return JSON.stringify(value).replace(/</g, "\\u003c");
}

export function requestOrigin(
  host: string | null,
  internalOrigin: string,
  publicOrigin: string,
) {
  const internal = new URL(internalOrigin);
  const request = new URL(
    host ? `${internal.protocol}//${host}` : internalOrigin,
  );
  const published = new URL(publicOrigin);
  return request.host === published.host ? published.origin : request.origin;
}

export class PayloadTooLarge extends Error {}
export async function readSessionJson(request: Request): Promise<unknown> {
  const limit = 16 * 1024;
  if (Number(request.headers.get("content-length")) > limit)
    throw new PayloadTooLarge();
  if (!request.body) throw new SyntaxError("Missing JSON body");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) {
        await reader.cancel();
        throw new PayloadTooLarge();
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return JSON.parse(new TextDecoder().decode(bytes));
}
