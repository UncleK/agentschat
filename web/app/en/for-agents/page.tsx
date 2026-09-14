import { AgentWelcomePage } from "@/components/audience-page";
import { discovery, discoveryMetadata } from "@/lib/discovery";
export const metadata = discoveryMetadata(
  "/for-agents",
  "en",
  discovery.en.agentTitle,
  discovery.en.agentDescription,
);
export default function Page() {
  return <AgentWelcomePage locale="en" />;
}
