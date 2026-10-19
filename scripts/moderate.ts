#!/usr/bin/env -S deno run --allow-env --allow-net --allow-read
import { z } from "https://esm.sh/zod@3.25.76";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const environment = z.object({ url: z.string().url(), key: z.string().min(1) }).parse({
  url: Deno.env.get("SUPABASE_URL"), key: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
});
const admin = createClient(environment.url, environment.key, { auth: { persistSession: false, autoRefreshToken: false } });
const [command, kind, id, decision, ...options] = Deno.args;
function option(name: string): string | undefined { const index = options.indexOf(name); return index < 0 ? undefined : options[index + 1]; }
async function rpc(name: string, args: Record<string, string> = {}) {
  const { data, error } = await admin.rpc(name, args);
  if (error) throw new Error(error.message);
  return data;
}
const rowSchema = z.object({
  id: z.string().uuid(), media_path: z.string().optional(), thumbnail_path: z.string().optional(), avatar_path: z.string().optional(),
}).passthrough();
async function previewRow(row: z.infer<typeof rowSchema>) {
  const previews: Record<string, string> = {};
  for (const field of ["media_path", "thumbnail_path", "avatar_path"] as const) {
    const path = row[field];
    if (!path) continue;
    const match = /^storage:\/\/(videos|thumbnails|avatars)\/(.+)$/.exec(path);
    if (!match) continue;
    const { data, error } = await admin.storage.from(match[1]).createSignedUrl(match[2], 900);
    if (error) throw error;
    previews[field] = data.signedUrl;
  }
  return { ...row, previews };
}
try {
  if (command === "queue") {
    const data = z.object({ videos: z.array(rowSchema), dogs: z.array(rowSchema), comments: z.array(rowSchema), reports: z.array(z.object({ id: z.string().uuid() }).passthrough()), oldest_open_report: z.string().nullable() }).parse(await rpc("moderation_queue"));
    const queue = { ...data, videos: await Promise.all(data.videos.map(previewRow)), dogs: await Promise.all(data.dogs.map(previewRow)) };
    console.log(JSON.stringify(queue, null, 2));
    if (queue.oldest_open_report && Date.now() - Date.parse(queue.oldest_open_report) > 24 * 3600 * 1000) {
      console.error("ACTION REQUIRED: a report has waited more than 24 hours.");
      Deno.exitCode = 2;
    }
  } else if (command === "inspect") {
    const table = kind === "video" ? "videos" : kind === "dog" ? "dogs" : kind === "comment" ? "comments" : kind === "report" ? "reports" : undefined;
    if (!table || !z.string().uuid().safeParse(id).success) throw new Error("Use inspect video|dog|comment|report UUID");
    const { data, error } = await admin.from(table).select("*").eq("id", id).single();
    if (error) throw error;
    console.log(JSON.stringify(await previewRow(rowSchema.parse(data)), null, 2));
  } else if (command === "review") {
    const body = z.object({
      target_kind: z.enum(["video", "dog", "comment", "report", "account"]), target_id: z.string().uuid(),
      decision: z.enum(["approve", "hide", "dismiss", "suspend", "restore"]), moderator_note: z.string().trim().min(3).max(1000),
      expected_revision: z.string().regex(/^\d+$/).optional(),
    }).parse({ target_kind: kind, target_id: id, decision, moderator_note: option("--note"), expected_revision: option("--revision") });
    if (body.target_kind === "dog" && body.decision === "approve" && !body.expected_revision) throw new Error("Pass --revision from the profile you actually inspected. Changed profiles require a fresh review.");
    const args: Record<string, string> = { target_kind: body.target_kind, target_id: body.target_id, decision: body.decision, moderator_note: body.moderator_note };
    if (body.expected_revision) args.expected_revision = body.expected_revision;
    await rpc("moderate_content", args);
    console.log("Recorded moderation decision. New media access is denied immediately for hidden content; issued links expire within 15 minutes.");
  } else if (command === "maintenance") {
    await rpc("prune_moderation_audit"); console.log("Removed moderation audit records older than 90 days.");
  } else {
    throw new Error("Commands: queue | inspect video|dog|comment|report UUID | review KIND UUID approve|hide|dismiss|suspend|restore --note REASON [--revision N] | maintenance");
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : "Moderation failed.");
  Deno.exitCode = 1;
}
