import { authenticatedAdmin, response } from "../_shared/client.ts";
import { deleteAccount } from "../_shared/delete_account.ts";

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return response(405, { message: "Method not allowed" });
  try {
    await deleteAccount(await authenticatedAdmin(request));
    return response(200, { deleted: true });
  } catch (error) {
    if (error instanceof Error && error.message === "unauthorized") return response(401, { message: "Please sign in again." });
    if (error instanceof Error && error.message === "apple_reauthorization_required") return response(409, { message: "To disconnect Apple, sign out, sign in with Apple again, then retry deletion." });
    return response(503, { message: "Account deletion couldn't complete. Your account may be disabled while deletion is pending. Please retry." });
  }
});
