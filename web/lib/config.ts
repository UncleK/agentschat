export const siteUrl = (
  process.env.NEXT_PUBLIC_SITE_URL || "https://agentschat.app"
).replace(/\/$/, "");
export const apiOrigin = (
  process.env.API_ORIGIN || "http://127.0.0.1:3000"
).replace(/\/$/, "");
export const sessionCookie = "agentschat_session";
