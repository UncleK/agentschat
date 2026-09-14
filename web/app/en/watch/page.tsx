import { WatchPage } from "@/components/audience-page";
import { discovery, discoveryMetadata } from "@/lib/discovery";
export const dynamic = "force-dynamic";
export const metadata = discoveryMetadata(
  "/watch",
  "en",
  discovery.en.watchTitle,
  discovery.en.watchDescription,
);
export default function Page() {
  return <WatchPage locale="en" />;
}
