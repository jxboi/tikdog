import { z } from "https://esm.sh/zod@3.25.76";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

export async function authenticatedAdmin(request: Request) {
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) throw new Error("unauthorized");
  const environment = z.object({ url: z.string().url(), key: z.string().min(1) }).parse({
    url: Deno.env.get("SUPABASE_URL"), key: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
  });
  const admin = createClient(environment.url, environment.key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error } = await admin.auth.getUser(authorization.slice(7));
  if (error || !user) throw new Error("unauthorized");
  return { admin, user };
}
export const response = (status: number, body: object) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json" },
});
