import { z } from "https://esm.sh/zod@3.25.76";
import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from "https://esm.sh/jose@5.10.0";

export const appleEnvironment = z.object({
  clientId: z.string().min(3), teamId: z.string().regex(/^[A-Z0-9]{10}$/),
  keyId: z.string().regex(/^[A-Z0-9]{10}$/), privateKey: z.string().min(100),
});
type AppleEnvironment = z.infer<typeof appleEnvironment>;
const appleKeys = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));
export function readAppleEnvironment(): AppleEnvironment {
  return appleEnvironment.parse({
    clientId: Deno.env.get("APPLE_CLIENT_ID"), teamId: Deno.env.get("APPLE_TEAM_ID"),
    keyId: Deno.env.get("APPLE_KEY_ID"), privateKey: Deno.env.get("APPLE_PRIVATE_KEY")?.replaceAll("\\n", "\n"),
  });
}
export async function appleClientSecret(config: AppleEnvironment): Promise<string> {
  return await new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: config.keyId })
    .setIssuer(config.teamId).setAudience("https://appleid.apple.com").setSubject(config.clientId)
    .setIssuedAt().setExpirationTime("5m").sign(await importPKCS8(config.privateKey, "ES256"));
}
export async function exchangeAppleCode(
  config: AppleEnvironment, code: string, expectedSubject: string,
  fetcher: typeof fetch = fetch, verificationKey: Parameters<typeof jwtVerify>[1] = appleKeys,
): Promise<string> {
  const result = await fetcher("https://appleid.apple.com/auth/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: config.clientId, client_secret: await appleClientSecret(config), code, grant_type: "authorization_code" }),
    signal: AbortSignal.timeout(15000),
  });
  if (!result.ok) throw new Error("Apple authorization could not be verified. Please sign in with Apple again.");
  const token = z.object({ id_token: z.string(), refresh_token: z.string().min(1) }).parse(await result.json());
  const { payload } = await jwtVerify(token.id_token, verificationKey, {
    algorithms: ["RS256"], issuer: "https://appleid.apple.com", audience: config.clientId, subject: expectedSubject,
  });
  if (payload.sub !== expectedSubject) throw new Error("Apple account does not match.");
  return token.refresh_token;
}
export async function revokeAppleToken(config: AppleEnvironment, refreshToken: string, fetcher: typeof fetch = fetch): Promise<void> {
  const result = await fetcher("https://appleid.apple.com/auth/revoke", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: config.clientId, client_secret: await appleClientSecret(config), token: refreshToken, token_type_hint: "refresh_token" }),
    signal: AbortSignal.timeout(15000),
  });
  if (!result.ok) throw new Error("Apple authorization could not be revoked. Please retry account deletion.");
}
