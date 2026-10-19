import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createClient, type User } from "https://esm.sh/@supabase/supabase-js@2.57.4";
import { deleteAccount } from "./delete_account.ts";

function fixture(options: { apple?: boolean; credentials?: boolean; revokeFails?: boolean; storageFails?: boolean } = {}) {
  const events: string[] = [];
  const user: User = { id: "33333333-3333-4333-8333-333333333333", app_metadata: {}, user_metadata: {}, aud: "authenticated", created_at: "2026-10-18T00:00:00Z", identities: options.apple ? [{ id: "apple-sub", identity_id: "apple-id", user_id: "33333333-3333-4333-8333-333333333333", provider: "apple", identity_data: { sub: "apple-sub" } }] : [] };
  const remaining = new Map<string, number>();
  const fetcher: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    const body: unknown = init?.body ? JSON.parse(String(init.body)) : null;
    if (url.pathname.endsWith("/apple_credentials_for_deletion")) return Response.json(options.credentials ? { refresh_token: "apple-refresh", apple_subject: "apple-sub" } : null);
    if (url.pathname.endsWith("/begin_account_deletion")) { events.push("freeze"); return Response.json(null); }
    if (url.pathname.startsWith("/storage/v1/object/list/")) {
      const bucket = url.pathname.split("/").at(-1)!;
      events.push(`list:${bucket}`);
      const count = remaining.get(bucket) ?? 0; remaining.set(bucket, count + 1);
      return Response.json(count === 0 ? [{ id: "object-id", name: "clip.mp4" }] : []);
    }
    if (url.pathname.startsWith("/storage/v1/object/")) {
      const bucket = url.pathname.split("/").at(-1)!;
      events.push(`remove:${bucket}`);
      if (options.storageFails) return Response.json({ message: "Storage unavailable" }, { status: 503 });
      assertEquals(body, { prefixes: [`${user.id}/clip.mp4`] });
      return Response.json([]);
    }
    if (url.pathname === `/auth/v1/admin/users/${user.id}`) { events.push("delete-user"); return Response.json({ user }); }
    throw new Error(`Unexpected request ${url.pathname}`);
  };
  const admin = createClient("https://supabase.test", "test-service-role", { auth: { persistSession: false, autoRefreshToken: false }, global: { fetch: fetcher } });
  const revoke = async (token: string) => { assertEquals(token, "apple-refresh"); events.push("revoke-apple"); if (options.revokeFails) throw new Error("Apple unavailable"); };
  return { admin, user, revoke, events };
}
Deno.test("deletion freezes writes, revokes Apple, removes all bucket bytes, then deletes identity", async () => {
  const f = fixture({ apple: true, credentials: true }); await deleteAccount(f, f.revoke);
  assertEquals(f.events, ["freeze", "revoke-apple", "list:videos", "remove:videos", "list:videos", "list:thumbnails", "remove:thumbnails", "list:thumbnails", "list:avatars", "remove:avatars", "list:avatars", "delete-user"]);
});
Deno.test("Apple reauthorization is requested before disabling a legacy account", async () => {
  const f = fixture({ apple: true }); await assertRejects(() => deleteAccount(f, f.revoke), Error, "apple_reauthorization_required"); assertEquals(f.events, []);
});
Deno.test("failed Apple revocation never erases account or media", async () => {
  const f = fixture({ apple: true, credentials: true, revokeFails: true }); await assertRejects(() => deleteAccount(f, f.revoke)); assertEquals(f.events, ["freeze", "revoke-apple"]);
});
Deno.test("storage failure keeps the identity available for retry", async () => {
  const f = fixture({ storageFails: true }); await assertRejects(() => deleteAccount(f, f.revoke)); assertEquals(f.events, ["freeze", "list:videos", "remove:videos"]);
});
Deno.test("email-only deletion does not require Apple configuration", async () => {
  const f = fixture(); await deleteAccount(f, f.revoke); assertEquals(f.events.includes("revoke-apple"), false); assertEquals(f.events.at(-1), "delete-user");
});
