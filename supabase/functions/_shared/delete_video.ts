import { z } from "https://esm.sh/zod@3.25.76";
import type { authenticatedAdmin } from "./client.ts";

type Authenticated = Awaited<ReturnType<typeof authenticatedAdmin>>;
export class VideoOwnershipError extends Error {}
export async function deleteVideo({ admin, user }: Authenticated, id: string): Promise<void> {
  const { data: video, error } = await admin.from("videos").select("id,dogs!inner(owner_id)").eq("id", id).maybeSingle();
  if (error) throw error;
  if (!video) return;
  const stored = z.object({ id: z.string().uuid(), dogs: z.object({ owner_id: z.string().uuid() }) }).parse(video);
  if (stored.dogs.owner_id !== user.id) throw new VideoOwnershipError("You can only delete your own videos.");
  for (const [bucket, extension] of [["videos", "mp4"], ["thumbnails", "jpg"]]) {
    const { error: storageError } = await admin.storage.from(bucket).remove([`${user.id}/${stored.id}.${extension}`]);
    if (storageError) throw storageError;
  }
  const { error: deleteError } = await admin.from("videos").delete().eq("id", stored.id);
  if (deleteError) throw deleteError;
}
