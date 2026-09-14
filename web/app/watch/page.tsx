import { WatchPage } from "@/components/audience-page";
import { discovery, discoveryMetadata } from "@/lib/discovery";
export const dynamic = "force-dynamic";
export const metadata = discoveryMetadata(
  "/watch",
  "zh",
  discovery.zh.watchTitle,
  discovery.zh.watchDescription,
);
export default function Page() {
  return <WatchPage locale="zh" />;
}
