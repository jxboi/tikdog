import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createLocalJWKSet, exportJWK, exportPKCS8, generateKeyPair, jwtVerify, SignJWT } from "https://esm.sh/jose@5.10.0";
import { appleClientSecret, exchangeAppleCode, revokeAppleToken } from "./apple.ts";

Deno.test("Apple code exchange verifies signature, audience and exact account before retaining the refresh token", async () => {
  const signing = await generateKeyPair("ES256", { extractable: true });
  const config = { clientId: "com.tikdog.app", teamId: "ABCDEFGHIJ", keyId: "0123456789", privateKey: await exportPKCS8(signing.privateKey) };
  const apple = await generateKeyPair("RS256", { extractable: true });
  const keys = createLocalJWKSet({ keys: [{ ...await exportJWK(apple.publicKey), kid: "apple-test", alg: "RS256" }] });
  const idToken = await new SignJWT({}).setProtectedHeader({ alg: "RS256", kid: "apple-test" }).setIssuer("https://appleid.apple.com").setAudience(config.clientId).setSubject("real-apple-person").setIssuedAt().setExpirationTime("5m").sign(apple.privateKey);
  const mock: typeof fetch = async (input, init) => {
    assertEquals(String(input), "https://appleid.apple.com/auth/token");
    const form = new URLSearchParams(String(init?.body));
    assertEquals(form.get("code"), "one-time-code");
    assertEquals(form.get("grant_type"), "authorization_code");
    assertEquals(form.get("client_id"), config.clientId);
    const secret = await jwtVerify(form.get("client_secret")!, signing.publicKey, { issuer: config.teamId, audience: "https://appleid.apple.com", subject: config.clientId, algorithms: ["ES256"] });
    assertEquals(secret.protectedHeader.kid, config.keyId);
    return Response.json({ id_token: idToken, refresh_token: "apple-refresh" });
  };
  assertEquals(await exchangeAppleCode(config, "one-time-code", "real-apple-person", mock, keys), "apple-refresh");
  await assertRejects(() => exchangeAppleCode(config, "one-time-code", "another-account", mock, keys));
  await assertRejects(() => exchangeAppleCode({ ...config, clientId: "another.app" }, "one-time-code", "real-apple-person", async () => Response.json({ id_token: idToken, refresh_token: "apple-refresh" }), keys));
  await assertRejects(() => exchangeAppleCode(config, "expired", "real-apple-person", async () => new Response("invalid_grant", { status: 400 }), keys));
});
Deno.test("Apple revocation sends the stored refresh token and fails closed on upstream failure", async () => {
  const signing = await generateKeyPair("ES256", { extractable: true });
  const config = { clientId: "com.tikdog.app", teamId: "ABCDEFGHIJ", keyId: "0123456789", privateKey: await exportPKCS8(signing.privateKey) };
  const secret = await appleClientSecret(config);
  await jwtVerify(secret, signing.publicKey, { subject: config.clientId, issuer: config.teamId });
  await revokeAppleToken(config, "stored-apple-refresh", async (input, init) => {
    assertEquals(String(input), "https://appleid.apple.com/auth/revoke");
    const form = new URLSearchParams(String(init?.body));
    assertEquals(form.get("token"), "stored-apple-refresh");
    assertEquals(form.get("token_type_hint"), "refresh_token");
    return new Response(null, { status: 200 });
  });
  await assertRejects(() => revokeAppleToken(config, "stored-apple-refresh", async () => new Response(null, { status: 503 })));
});
