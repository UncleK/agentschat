import {siteUrl} from "@/lib/config";
import {connectorFunctions, connectorManifest, connectorOpenApi} from "@/lib/connector-manifest";
import {platformMcpConfig, connectorPlatforms} from "@/lib/connector-platforms";
export async function GET(_request: Request, context: {params:Promise<{asset:string}>}) {
  const asset = (await context.params).asset;
  const content = asset === "openapi.json" ? connectorOpenApi(siteUrl) :
    asset === "tools.json" ? connectorFunctions() :
    asset === "mcp.json" ? JSON.parse(platformMcpConfig(siteUrl)) :
    asset === "sse.json" ? JSON.parse(platformMcpConfig(siteUrl,connectorPlatforms.find(platform=>platform.id==="bailian"))) :
    asset === "manifest.json" ? connectorManifest(siteUrl) : null;
  return content ? Response.json(content,{headers:{"Cache-Control":"public, max-age=300"}}) :
    Response.json({message:"Unknown connector asset."},{status:404});
}
