#!/usr/bin/env -S deno run --allow-env --allow-net --allow-read --allow-write
/** Runs against a disposable/staging Supabase project. Creates two accounts and removes them. */
import { z } from "https://esm.sh/zod@3.25.76";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const config = z.object({ url: z.string().url(), key: z.string().min(1), publicKey: z.string().min(1), allowWrites: z.literal("YES") }).parse({
  url: Deno.env.get("SUPABASE_URL"), key: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"), publicKey: Deno.env.get("SUPABASE_PUBLISHABLE_KEY"), allowWrites: Deno.env.get("TIKDOG_SMOKE_ALLOW_WRITE"),
});
const root = new URL("../", import.meta.url);
const evidencePath = new URL(".build-artifacts/live-smoke.json", root);
// A failed rerun must not leave an earlier pass as current release evidence.
try { await Deno.remove(evidencePath); } catch (error) { if (!(error instanceof Deno.errors.NotFound)) throw error; }
const admin = createClient(config.url, config.key, { auth: { persistSession: false, autoRefreshToken: false } });
const makeClient = () => createClient(config.url, config.publicKey, { auth: { persistSession: false, autoRefreshToken: false } });
const guest = makeClient(), owner = makeClient(), other = makeClient();
const accounts: string[] = [];
const checks: string[] = [];
const dogId = crypto.randomUUID(), videoId = crypto.randomUUID();
const assert = (value: unknown, message: string): void => { if (!value) throw new Error(message); checks.push(message); };
const videoSchema = z.object({ id: z.string().uuid(), status: z.enum(["pending", "ready", "hidden"]) });
const dogSchema = z.object({ id: z.string().uuid(), status: z.string(), review_revision: z.number().optional() });
const commentSchema = z.object({ id: z.string().uuid(), status: z.string() });
const commentsSchema = z.array(z.object({ id: z.string().uuid() }));
async function createAccount(client: ReturnType<typeof makeClient>) {
  const email = `tikdog-smoke-${crypto.randomUUID()}@example.invalid`;
  const { data, error } = await admin.auth.admin.createUser({ email, email_confirm: true });
  if (error || !data.user) throw new Error("Could not create disposable test account");
  accounts.push(data.user.id);
  // Admin-generated test tokens do not send email or enable a public email sign-in flow.
  const link = await admin.auth.admin.generateLink({ type: "magiclink", email });
  if (link.error || !link.data.properties?.hashed_token) throw new Error("Disposable test token creation failed");
  const login = await client.auth.verifyOtp({ token_hash: link.data.properties.hashed_token, type: "magiclink" });
  if (login.error) throw new Error("Disposable account login failed");
  const terms = await client.rpc("accept_terms", { terms_version: "2026-10-18" });
  if (terms.error) throw new Error("Terms acceptance failed");
  return data.user.id;
}
try {
  const ownerId = await createAccount(owner); await createAccount(other);
  const dog = await owner.rpc("save_dog", { dog_id: dogId, dog_name: "Release test dog", dog_breed: "Mix", dog_birthday: "", dog_bio: "Disposable release verification", dog_avatar: "" });
  if (dog.error) throw new Error(dog.error.message);
  assert(dogSchema.parse(dog.data).status === "pending", "new profile is quarantined");
  const movie = await Deno.readFile(new URL("TikDog/Resources/Media/cabby.mp4", root));
  const cover = await Deno.readFile(new URL("TikDog/Resources/Media/cabby.jpg", root));
  const videoPath = `${ownerId}/${videoId}.mp4`, coverPath = `${ownerId}/${videoId}.jpg`;
  const upload = await owner.storage.from("videos").upload(videoPath, movie, { contentType: "video/mp4" });
  const thumbnail = await owner.storage.from("thumbnails").upload(coverPath, cover, { contentType: "image/jpeg" });
  if (upload.error || thumbnail.error) throw new Error("Hosted Storage upload failed");
  const published = await owner.rpc("publish_video", { video_id: videoId, featured_dog: dogId, video_caption: "Disposable release clip", video_tags: "releasecheck", media_url: `storage://videos/${videoPath}`, thumbnail_url: `storage://thumbnails/${coverPath}`, duration_seconds: "3.4" });
  if (published.error) throw new Error(published.error.message);
  assert(videoSchema.parse(published.data).status === "pending", "new video is quarantined");
  assert((await guest.from("videos").select("id").eq("id", videoId)).data?.length === 0, "guest cannot read pending video metadata");
  assert(Boolean((await guest.storage.from("videos").createSignedUrl(videoPath, 900)).error), "guest cannot sign pending video bytes");
  assert(!(await fetch(`${config.url}/storage/v1/object/public/videos/${videoPath}`)).ok, "public object endpoint cannot bypass quarantine");
  let result = await admin.rpc("moderate_content", { target_kind: "dog", target_id: dogId, decision: "approve", moderator_note: "Inspected disposable smoke profile", expected_revision: "1" });
  if (result.error) throw new Error(result.error.message);
  result = await admin.rpc("moderate_content", { target_kind: "video", target_id: videoId, decision: "approve", moderator_note: "Inspected licensed fixture" });
  if (result.error) throw new Error(result.error.message);
  const signedResponse = await fetch(`${config.url}/storage/v1/object/sign/videos`, { method: "POST", headers: { apikey: config.publicKey, "Content-Type": "application/json", ...(config.publicKey.startsWith("sb_publishable_") ? {} : { Authorization: `Bearer ${config.publicKey}` }) }, body: JSON.stringify({ paths: [videoPath], expiresIn: 900 }) });
  assert(signedResponse.ok, "native batch signing endpoint works for approved guest content");
  const signed = z.array(z.object({ path: z.string(), signedURL: z.string() })).parse(await signedResponse.json());
  const bytes = await fetch(`${config.url}/storage/v1${signed[0].signedURL}`);
  assert(bytes.ok && (await bytes.arrayBuffer()).byteLength === movie.byteLength, "approved signed video delivers the original bytes");
  const comment = await other.rpc("add_comment", { target_video: videoId, comment_body: "A safe disposable comment" });
  if (comment.error) throw new Error(comment.error.message);
  const parsedComment = commentSchema.parse(comment.data);
  assert(parsedComment.status === "pending", "comment is quarantined");
  assert(!commentsSchema.parse((await guest.rpc("get_comments", { target_video: videoId })).data).some((row) => row.id === parsedComment.id), "guest cannot read pending comments");
  result = await admin.rpc("moderate_content", { target_kind: "comment", target_id: parsedComment.id, decision: "approve", moderator_note: "Safe fixture comment" });
  if (result.error) throw new Error(result.error.message);
  result = await owner.rpc("report_content", { target_kind: "comment", target_id: parsedComment.id, report_reason: "inappropriate" });
  assert(!result.error && !commentsSchema.parse((await owner.rpc("get_comments", { target_video: videoId })).data).some((row) => row.id === parsedComment.id), "comment reporting works and immediately hides it");
  result = await admin.rpc("moderate_content", { target_kind: "video", target_id: videoId, decision: "hide", moderator_note: "Removal smoke check" });
  if (result.error) throw new Error(result.error.message);
  assert(Boolean((await guest.storage.from("videos").createSignedUrl(videoPath, 900)).error), "hidden video cannot receive new guest access links");
  const deletion = await owner.functions.invoke("delete-account", { body: {} });
  assert(!deletion.error, "deployed account deletion completes");
  const removed = await admin.auth.admin.getUserById(ownerId);
  assert(Boolean(removed.error), "deleted auth identity is gone");
  const objects = await admin.storage.from("videos").list(ownerId);
  assert(!objects.error && objects.data.length === 0, "deleted account leaves no video objects");
} finally {
  for (const id of accounts) {
    for (const bucket of ["videos", "thumbnails", "avatars"]) {
      const { data, error } = await admin.storage.from(bucket).list(id);
      if (error) throw new Error(`Test cleanup failed listing ${bucket}; remove disposable account ${id} using the dashboard`);
      if (data.length) {
        const removal = await admin.storage.from(bucket).remove(data.map((file) => `${id}/${file.name}`));
        if (removal.error) throw new Error(`Test cleanup failed removing ${bucket}; remove disposable account ${id} using the dashboard`);
      }
    }
    // A successfully deleted account is already absent; admin delete errors then are harmless.
    const remaining = await admin.auth.admin.getUserById(id);
    if (remaining.data.user) {
      const deletion = await admin.auth.admin.deleteUser(id);
      if (deletion.error) throw new Error(`Remove disposable test account ${id} in the dashboard`);
    }
  }
}
// Publish success only after cleanup has also completed successfully.
const evidence = { passed: true, verified_at: new Date().toISOString(), backend_url: config.url, checks };
await Deno.mkdir(new URL(".build-artifacts/", root), { recursive: true });
await Deno.writeTextFile(evidencePath, JSON.stringify(evidence, null, 2));
console.log(`PASS: ${checks.length} live auth, moderation, private storage, reporting and deletion checks; disposable test data cleaned up. Evidence: .build-artifacts/live-smoke.json`);
