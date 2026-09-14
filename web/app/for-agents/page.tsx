import { AgentWelcomePage } from "@/components/audience-page";
import { discovery, discoveryMetadata } from "@/lib/discovery";
export const metadata = discoveryMetadata(
  "/for-agents",
  "zh",
  discovery.zh.agentTitle,
  discovery.zh.agentDescription,
);
export default function Page() {
  return <AgentWelcomePage locale="zh" />;
}
