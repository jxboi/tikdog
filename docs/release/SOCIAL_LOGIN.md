# Facebook and Apple sign-in

The user selected Facebook and Apple only on October 18, 2026. Supabase manages identities and sessions; TikDog does not collect provider passwords and has no email/password signup, sign-in or password reset. Users can browse approved content as guests. Account deletion and moderation still apply to the application's own user data.

## Current implementation and setup

The app has a native Sign in with Apple button and a Facebook button that opens ASWebAuthenticationSession. Both require the existing age/terms consent. Facebook uses a random 256-bit PKCE verifier stored only for the current attempt. The callback must be exactly `tikdog://auth/callback` with one authorization code; it cannot inject access tokens from fragments. The app exchanges the code with Supabase before saving its session in Keychain. Cancellation, replay, an overlapping attempt, and sign-out invalidate older attempts.

All 26 Swift tests pass. A connected-app UI test passes on iOS 17 and 26.5, verifying both provider buttons, consent gating, absence of password fields/reset and return to guest browsing. This does not prove a real Facebook or Apple account login. See `docs/VERIFICATION.md`.

The linked Supabase project is `scgoiuhfnhpuhftgmegx`. Its callback allow list includes the social callback, added without removing the existing email redirects or provider. Automatic approval review rejected disabling the current provider before replacements were configured and verified because that could lock users out. The native app already offers social sign-in only; complete the hosted cutover after the providers work.

TikDog's separate Meta app is created: **App ID 1422143516770927**, [Meta dashboard](https://developers.facebook.com/apps/1422143516770927/dashboard/). The user approved its existing developer contact email, Meta terms, required email permission, exact callback and server credential connection. That developer email is not the deferred public support identity. Both `public_profile` and `email` show **Ready for testing**, and the exact Supabase OAuth callback is saved.

TikDog's App Secret was transferred directly in memory from the authorized Meta UI field into the server-side Supabase Facebook provider and discarded from the automation variable after saving. The provider now shows **ENABLED**. Public Auth settings independently confirm Facebook enabled, and the PKCE authorization endpoint redirects to TikDog's App ID and the exact callback. The real browser flow reaches Facebook's consent page requesting name/profile picture and email. No consent was granted and no user code/session was exchanged during that entry check. **Completed user login and Facebook-linked account deletion remain unverified.**

Meta's app is still unpublished. Its consent page warns that Login Review is required; business verification, public policies/deletion instructions and other publishing requirements remain open. Evidence is saved in `.build-artifacts/facebook-provider-status.json` and `.build-artifacts/facebook-setup-evidence.json`, without credentials. Apple remains disabled, and the existing hosted email provider stays enabled until the verified social-only cutover.

## Meta and Supabase settings

1. Create the separate TikDog Meta app using the Facebook Login use case. Do not modify the user's other Meta apps. Business portfolio selection can be deferred during development; the current Meta creation flow lists business verification and App Review as publishing requirements.
2. In Facebook Login settings, add the exact valid OAuth redirect URI:
   `https://scgoiuhfnhpuhftgmegx.supabase.co/auth/v1/callback`.
3. Ensure both `public_profile` and `email` permissions are available for the login use case. Supabase's Facebook provider requires the email permission. Request no friends, posts, advertising or other permissions.
4. In Supabase Authentication > Sign In / Providers > Facebook, configure the TikDog App ID and App Secret and enable the provider. Keep the secret only in Supabase's server-side provider configuration. Do not put it in iOS settings, source, screenshots, test logs or chat.
5. Configure Apple for the actual bundle ID and set the Apple revocation secrets documented in OPERATIONS.md. Paid Apple Developer enrollment remains outstanding.
6. Configure real public privacy, terms, support and data-deletion instructions for Meta's required fields. The shared support page describes in-app deletion and requesting help if the user cannot access the app. The operator/contact/domain details remain deferred; do not invent them. Complete current Meta data-handling/review requirements and verify access for a user who has no developer/tester role.

The hosted OAuth callback above belongs in Meta. The native `tikdog://auth/callback` belongs in Supabase's redirect allow list. They serve different steps of the same flow.

## Safe provider cutover

The additive setup is in `supabase/operations/native-auth/supabase/config.toml`. Preview it with `supabase config diff --workdir supabase/operations/native-auth --project-ref scgoiuhfnhpuhftgmegx` before applying changes.

Only after real Facebook and Apple login/cancellation/deletion are verified, preview `supabase config diff --workdir supabase/operations/social-only --project-ref scgoiuhfnhpuhftgmegx`. That separate final config disables the email provider and removes obsolete email redirects. Apply it only when replacement access is ready, then confirm the public Auth settings have Facebook and Apple enabled and email disabled. Retest both social providers and update their release evidence. Do not push the entire local-development config to the hosted project.

There is no SMTP requirement for this product choice. Password or access recovery happens through Facebook/Apple. Account-linking behavior is managed by Supabase; test the chosen providers with the actual privacy/relay email settings rather than assuming the same address always maps to one identity.

## Required proof

Test real Facebook success, denied permissions/cancellation, app termination/retry, session persistence/refresh, sign-out, and deleting a Facebook-linked TikDog identity and media. Confirm deleting TikDog does not delete the person's Facebook account. Test Apple sign-in, reauthorization and revocation on hardware. Confirm guest browsing still works. The backend smoke harness uses admin-created disposable identities and verification tokens without sending email; it verifies the backend separately and does not replace either social-provider test.

Record Facebook proof, including the final provider configuration, in `facebook_signin_and_deletion` and Apple proof in `apple_signin_and_revocation` in ignored `release/live-evidence.json`. Leave these false until verified. Reviewer access must use the supported social flows; do not claim the app offers an email/password reviewer login.

Sources: [Supabase Facebook setup](https://supabase.com/docs/guides/auth/social-login/auth-facebook), [Supabase PKCE flow](https://supabase.com/docs/guides/auth/sessions/pkce-flow), and [Apple review guideline 4.8](https://developer.apple.com/app-store/review/guidelines/#login-services). Meta's current account-specific publishing requirements were read from the actual TikDog creation form; they remain unfulfilled.

The Meta Basic page currently reports missing App icon (1024 × 1024), Privacy policy URL, User data deletion, and Category for submission eligibility. These are separate from the saved development OAuth callback. Do not invent public policy or contact details to clear them.
