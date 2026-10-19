import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createClient, type User } from "https://esm.sh/@supabase/supabase-js@2.57.4";
import { deleteVideo, VideoOwnershipError } from "./delete_video.ts";
import { authenticatedAdmin } from "./client.ts";

const videoId = "10000000-0000-4000-8000-000000000033";
function fixture(options: { foreign?: boolean; missing?: boolean; storageFailure?: boolean } = {}) {
  const user: User = { id: "33333333-3333-4333-8333-333333333333", app_metadata: {}, user_metadata: {}, aud: "authenticated", created_at: "2026-10-18T00:00:00Z" };
  const events: string[] = [];
  const fetcher: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    if (url.pathname === "/rest/v1/videos" && init?.method !== "DELETE") return Response.json(options.missing ? null : { id: videoId, dogs: { owner_id: options.foreign ? "44444444-4444-4444-8444-444444444444" : user.id } });
    if (url.pathname.startsWith("/storage/v1/object/")) {
      const bucket = url.pathname.split("/").at(-1)!; events.push(`remove:${bucket}`);
      if (options.storageFailure) return Response.json({ message: "Unavailable" }, { status: 503 });
      assertEquals(JSON.parse(String(init?.body)), { prefixes: [`${user.id}/${videoId}.${bucket === "videos" ? "mp4" : "jpg"}`] });
      return Response.json([]);
    }
    if (url.pathname === "/rest/v1/videos" && init?.method === "DELETE") { events.push("delete-row"); return Response.json(null); }
    throw new Error("Unexpected request");
  };
  const admin = createClient("https://supabase.test", "service-key", { auth: { persistSession: false, autoRefreshToken: false }, global: { fetch: fetcher } });
  return { admin, user, events };
}
Deno.test("video deletion removes owned bytes before metadata and permits idempotent retries", async () => {
  const f = fixture(); await deleteVideo(f, videoId); assertEquals(f.events, ["remove:videos", "remove:thumbnails", "delete-row"]);
  const absent = fixture({ missing: true }); await deleteVideo(absent, videoId); assertEquals(absent.events, []);
});
Deno.test("another owner's video cannot be removed", async () => {
  const f = fixture({ foreign: true }); await assertRejects(() => deleteVideo(f, videoId), VideoOwnershipError); assertEquals(f.events, []);
});
Deno.test("failed video byte removal retains metadata for retry", async () => {
  const f = fixture({ storageFailure: true }); await assertRejects(() => deleteVideo(f, videoId)); assertEquals(f.events, ["remove:videos"]);
});
Deno.test("destructive functions reject requests without a bearer identity before reading server credentials", async () => {
  for (const authorization of [undefined, "Basic anonymous", ""]) {
    await assertRejects(() => authenticatedAdmin(new Request("https://supabase.test/functions/v1/delete-account", { headers: authorization ? { Authorization: authorization } : {} })), Error, "unauthorized");
  }
});
