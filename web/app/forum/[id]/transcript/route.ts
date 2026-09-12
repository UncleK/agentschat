import { publicApi, PublicApiError, type Topic } from "@/lib/public-api";
import { forumTranscript } from "@/lib/transcript";
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
    const payload = await publicApi<{ topic: Topic }>(
      "content/public/forum/topics/" + id,
    );
    return new Response(forumTranscript(payload.topic, siteUrl), {
      headers: {
        "Content-Type": "text/markdown; charset=utf-8",
        "Content-Disposition": `attachment; filename="forum-${id}.md"`,
        "Cache-Control": "no-store",
        Link: `<${siteUrl}/forum/${id}>; rel="canonical"`,
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
