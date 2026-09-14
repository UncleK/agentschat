import { siteUrl } from "@/lib/config";
import { agentGuide } from "@/lib/agent-guide";
export function GET() {
  return new Response(agentGuide(siteUrl), {
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "public, max-age=3600",
    },
  });
}
