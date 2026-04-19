import { HTTP_USER_AGENT, SLOT_PATTERN } from "./constants.js";
import type { AgentsChatMode, AgentsChatTransport } from "./types.js";

export class AgentsChatHttpError extends Error {
  readonly method: string;
  readonly url: string;
  readonly statusCode: number;
  readonly details: string;

  constructor(method: string, url: string, statusCode: number, details: string) {
    super(`HTTP ${statusCode} for ${method} ${url}: ${details}`);
    this.method = method;
    this.url = url;
    this.statusCode = statusCode;
    this.details = details;
  }
}

export class AgentsChatNetworkError extends Error {
  readonly method: string;
  readonly url: string;
  readonly details: string;

  constructor(method: string, url: string, details: string) {
    super(`Network error for ${method} ${url}: ${details}`);
    this.method = method;
    this.url = url;
    this.details = details;
  }
}

export function normalizeBaseUrl(value: string): string {
  return value.replace(/\/+$/, "");
}

export function normalizeMode(value: string | null | undefined): AgentsChatMode {
  return value === "bound" ? "bound" : "public";
}

export function normalizeTransport(value: string | null | undefined): AgentsChatTransport {
  return value === "hybrid" ? "hybrid" : "polling";
}

export function normalizeSlot(value: string): string {
  const normalized = value.trim().replace(SLOT_PATTERN, "-").replace(/^[.\-_]+|[.\-_]+$/g, "");
  if (normalized.length === 0) {
    throw new Error("slot must contain at least one valid character.");
  }
  return normalized;
}

export function parseLauncherUrl(launcherUrl: string): Record<string, string> {
  const parsed = new URL(launcherUrl);
  if (parsed.protocol !== "agents-chat:" || parsed.hostname !== "launch") {
    throw new Error("Launcher URL must use agents-chat://launch");
  }

  const values: Record<string, string> = {};
  parsed.searchParams.forEach((value, key) => {
    if (value.length > 0) {
      values[key] = value;
    }
  });
  return values;
}

export function handleVariants(baseHandle: string): string[] {
  const normalized = baseHandle
    .trim()
    .toLowerCase()
    .replace(SLOT_PATTERN, "-")
    .replace(/_/g, "-")
    .replace(/^[.\-_]+|[.\-_]+$/g, "")
    .slice(0, 56) || "agent";
  const values = [normalized];
  while (values.length < 7) {
    const suffix = Math.random().toString(16).slice(2, 6);
    const candidate = `${normalized.slice(0, 59).replace(/-+$/g, "")}-${suffix}`;
    if (!values.includes(candidate)) {
      values.push(candidate);
    }
  }
  return values;
}

export function buildHeaders(accessToken?: string, extraHeaders?: HeadersInit): Headers {
  const headers = new Headers({
    Accept: "application/json",
    "Accept-Language": "en-US,en;q=0.9",
    "Content-Type": "application/json",
    "User-Agent": HTTP_USER_AGENT
  });
  if (accessToken) {
    headers.set("Authorization", `Bearer ${accessToken}`);
  }
  if (extraHeaders) {
    new Headers(extraHeaders).forEach((value, key) => headers.set(key, value));
  }
  return headers;
}

export async function httpJson<T>(
  method: string,
  url: string,
  payload?: unknown,
  accessToken?: string,
  extraHeaders?: HeadersInit
): Promise<T> {
  try {
    const response = await fetch(url, {
      method,
      headers: buildHeaders(accessToken, extraHeaders),
      body: payload == null ? undefined : JSON.stringify(payload)
    });

    const rawBody = await response.text();
    if (!response.ok) {
      throw new AgentsChatHttpError(method, url, response.status, rawBody);
    }

    if (rawBody.length === 0) {
      return {} as T;
    }
    return JSON.parse(rawBody) as T;
  } catch (error) {
    if (error instanceof AgentsChatHttpError) {
      throw error;
    }
    const details = error instanceof Error ? error.message : String(error);
    throw new AgentsChatNetworkError(method, url, details);
  }
}

export async function putBinary(
  url: string,
  payload: Uint8Array,
  headers?: HeadersInit
): Promise<void> {
  try {
    const response = await fetch(url, {
      method: "PUT",
      headers: headers ? new Headers(headers) : undefined,
      body: payload as unknown as BodyInit
    });

    if (!response.ok) {
      throw new AgentsChatHttpError("PUT", url, response.status, await response.text());
    }
  } catch (error) {
    if (error instanceof AgentsChatHttpError) {
      throw error;
    }
    const details = error instanceof Error ? error.message : String(error);
    throw new AgentsChatNetworkError("PUT", url, details);
  }
}

export async function wait(ms: number, abortSignal?: AbortSignal): Promise<void> {
  if (ms <= 0) {
    return;
  }
  await new Promise<void>((resolve, reject) => {
    const timer = setTimeout(resolve, ms);
    if (abortSignal) {
      const onAbort = () => {
        clearTimeout(timer);
        reject(new Error("aborted"));
      };
      if (abortSignal.aborted) {
        onAbort();
        return;
      }
      abortSignal.addEventListener("abort", onAbort, { once: true });
    }
  });
}
