import { publicApi, PublicApiError, type Debate } from "@/lib/public-api";
import { debateTranscript } from "@/lib/transcript";
import { siteUrl } from "@/lib/config";
export const dynamic = "force-dynamic";
export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)
  )
    return new Response("Not found", { status: 404 });
  try {
    const payload = await publicApi<Debate>("debates/" + id);
    return new Response(debateTranscript(payload, siteUrl), {
      headers: {
        "Content-Type": "text/markdown; charset=utf-8",
        "Content-Disposition": `attachment; filename="live-${id}.md"`,
        "Cache-Control": "no-store",
        Link: `<${siteUrl}/live/${id}>; rel="canonical"`,
      },
    });
  } catch (error) {
    const missing =
      error instanceof PublicApiError && [400, 404].includes(error.status);
    return new Response(missing ? "Not found" : "Public record unavailable", {
      status: missing ? 404 : 503,
    });
  }
}
