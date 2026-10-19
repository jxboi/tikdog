import { z } from "https://esm.sh/zod@3.25.76";
import { authenticatedAdmin, response } from "../_shared/client.ts";
import { exchangeAppleCode, readAppleEnvironment } from "../_shared/apple.ts";

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return response(405, { message: "Method not allowed" });
  try {
    const { admin, user } = await authenticatedAdmin(request);
    const body = z.object({ authorization_code: z.string().min(1).max(4096) }).safeParse(await request.json().catch(() => null));
    if (!body.success) return response(400, { message: "Apple authorization is required." });
    const identity = user.identities?.find((item) => item.provider === "apple");
    const subject = z.string().min(1).safeParse(identity?.identity_data?.sub);
    if (!subject.success) return response(403, { message: "Sign in with your Apple account first." });
    const refreshToken = await exchangeAppleCode(readAppleEnvironment(), body.data.authorization_code, subject.data);
    const { error } = await admin.rpc("store_apple_credentials", { target_user: user.id, apple_subject: subject.data, apple_refresh_token: refreshToken });
    if (error) throw error;
    return response(200, { registered: true });
  } catch (error) {
    const unauthorized = error instanceof Error && error.message === "unauthorized";
    return response(unauthorized ? 401 : 503, { message: unauthorized ? "Please sign in again." : "Apple authorization couldn't be saved. Please sign in with Apple again before deleting your account." });
  }
});
