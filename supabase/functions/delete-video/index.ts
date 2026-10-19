import { z } from "https://esm.sh/zod@3.25.76";
import { authenticatedAdmin, response } from "../_shared/client.ts";
import { deleteVideo, VideoOwnershipError } from "../_shared/delete_video.ts";

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return response(405, { message: "Method not allowed" });
  try {
    const authenticated = await authenticatedAdmin(request);
    const body = z.object({ video_id: z.string().uuid() }).safeParse(await request.json().catch(() => null));
    if (!body.success) return response(400, { message: "Invalid video." });
    await deleteVideo(authenticated, body.data.video_id);
    return response(200, { deleted: true });
  } catch (error) {
    if (error instanceof VideoOwnershipError) return response(403, { message: error.message });
    const unauthorized = error instanceof Error && error.message === "unauthorized";
    return response(unauthorized ? 401 : 503, { message: unauthorized ? "Please sign in again." : "Video deletion couldn't complete. Please retry." });
  }
});
