import { z } from "https://esm.sh/zod@3.25.76";
import type { authenticatedAdmin } from "./client.ts";
import { readAppleEnvironment, revokeAppleToken } from "./apple.ts";

type Authenticated = Awaited<ReturnType<typeof authenticatedAdmin>>;
export async function deleteAccount({ admin, user }: Authenticated, revoke: (token: string) => Promise<void> = (token) => revokeAppleToken(readAppleEnvironment(), token)): Promise<void> {
  const appleUser = user.identities?.some((identity) => identity.provider === "apple") ?? false;
  const { data: stored, error: credentialError } = await admin.rpc("apple_credentials_for_deletion", { target_user: user.id });
  if (credentialError) throw credentialError;
  const credential = z.object({ refresh_token: z.string().min(1), apple_subject: z.string().min(1) }).nullable().parse(stored);
  if (appleUser && !credential) throw new Error("apple_reauthorization_required");
  const { error: freezeError } = await admin.rpc("begin_account_deletion", { target_user: user.id });
  if (freezeError) throw freezeError;
  // All content/storage inserts now fail server-side, including from other devices.
  if (credential) await revoke(credential.refresh_token);
  for (const bucket of ["videos", "thumbnails", "avatars"]) {
    const removePrefix = async (prefix: string): Promise<void> => {
      while (true) {
        const { data: files, error } = await admin.storage.from(bucket).list(prefix, { limit: 100 });
        if (error) throw error;
        if (!files?.length) return;
        const objects: string[] = [];
        for (const file of files) {
          const path = `${prefix}/${file.name}`;
          if (file.id) objects.push(path);
          else await removePrefix(path);
        }
        if (objects.length) {
          const { error: removalError } = await admin.storage.from(bucket).remove(objects);
          if (removalError) throw removalError;
        }
      }
    };
    await removePrefix(user.id);
  }
  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) throw error;
}
