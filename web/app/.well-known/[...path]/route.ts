import { apiOrigin, siteUrl } from "@/lib/config";
export const dynamic = "force-dynamic";
export async function GET(_request: Request, context: {params: Promise<{path: string[]}>}) {
  const path = (await context.params).path.join("/");
  let endpoint: string;
  if (path === "oauth-authorization-server") endpoint = "metadata";
  else if (["oauth-protected-resource", "oauth-protected-resource/api/v1/connectors/mcp", "oauth-protected-resource/api/v1/connectors/sse"].includes(path))
    endpoint = "resource?resource=" + encodeURIComponent(siteUrl + (path.endsWith("/sse") ? "/api/v1/connectors/sse" : "/api/v1/connectors/mcp"));
  else return Response.json({message: "Unknown metadata."}, {status:404});
  try {
    const response = await fetch(apiOrigin + "/api/v1/connectors/oauth/" + endpoint,
      {cache:"no-store", redirect:"error", signal:AbortSignal.timeout(10000)});
    return new Response(response.body,{status:response.status,headers:{"Content-Type":"application/json","Cache-Control":"no-store"}});
  } catch { return Response.json({message:"Connector unavailable."},{status:503}); }
}
