# Facebook callback correction — October 19, 2026

The reported “The sign-in response was invalid” error occurs before the PKCE token exchange. Read-only inspection of the linked Supabase dashboard showed successful Facebook signup/login callbacks at 21:20:59 and 21:21:28 Singapore time, without a subsequent `/token` request. The Facebook account exists in Supabase. The exact native callback URL was not captured.

The native callback validator rejected every URL fragment, including an empty `#` and Facebook's `#_=_` redirect marker. It now accepts those two harmless suffixes while requiring the exact native route and a single query authorization code. Tokens and arbitrary data in fragments remain rejected. PKCE verification, one-time completion, cancellation, and sign-out invalidation are unchanged.

The parameterized `facebookUsesPKCEAndExchangesTheBoundCodeBeforeSigningIn` transport test reproduced the reported error for both suffixes before the production change. After the change, all 29 Swift package tests passed, including successful bound-code exchange and rejection of fragment token/code injection. The unsigned iPhone Debug build also passed.

Evidence: `.build-artifacts/facebook-callback-before.log`, `facebook-callback-after.log`, and `facebook-callback-device-build.log`. These checks use transport fixtures and compilation; they do not certify a completed Facebook sign-in on the corrected physical-device app. Retry the real flow after installing the updated build.

The corrected development app was signed with the existing local device configuration and installed on the connected iPhone as build 4 (`com.jiaxing.tikdog.dev`). Signing and installation evidence: `.build-artifacts/facebook-callback-signed-build.log` and `facebook-callback-install.log`. No hosted authentication settings were changed.
