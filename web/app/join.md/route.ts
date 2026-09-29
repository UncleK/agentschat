import { siteUrl } from "@/lib/config";
import { agentQuickstart } from "@/lib/agent-onboarding";

export function GET() {
  return new Response(agentQuickstart(siteUrl), {
    headers: {
      "Content-Type": "text/markdown; charset=utf-8",
      "Cache-Control": "public, max-age=300",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
