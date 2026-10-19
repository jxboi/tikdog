# App Store preparation

Branding is unchanged. Completion means: unapproved content and media cannot be publicly accessed; users can report videos, comments and profiles and block abusive accounts; moderators can review and remove content and suspend accounts; published terms/privacy/support are configured; Apple authorization is revoked before deleting an Apple account; Facebook/Apple login and session termination work without app-managed passwords; release builds cannot silently become an offline demo; the live backend and signed hardware flows pass release verification.

## Work units

- [x] Database: pending review for videos/comments/profiles, private media, moderator authorization/audit, reports, terms acceptance, suspension and deletion lock.
- [x] Client: moderation states, comment/profile safety controls, blocked account management, terms consent, accurate legal/support screens, private media access.
- [x] Authentication implementation: Facebook PKCE, Apple authorization exchange/storage/revocation, reliable sign-out/session refresh; email/password/recovery removed at user request.
- [x] Operations artifacts: usable moderation CLI, policy/support website sources, release configuration validation, live smoke harness and submission notes.
- [x] Local verification: real PostgreSQL security tests, Swift behavior/transport tests, Edge Function tests, simulator safety flows, release build and direct artifact inspection.
- [x] Hosted backend baseline: four migrations and three Edge Functions deployed, 14 live smoke checks passed, native guest screen verified, redirect URLs configured and approved retention scheduler execution verified.
- [ ] Remaining launch gate: real Facebook/Apple flows and the final social-only provider cutover, published operator details/policies, moderation staffing, Apple Developer enrollment/signing and physical-device/TestFlight checks.

## User deferrals

On October 18, 2026 the user said operator/support/domain details should be left for later and that they do not have a paid Apple Developer account. Prepare these surfaces without inventing details; do not label submission readiness complete while required external gates remain unverified.

## Approach

All new public contributions wait for a human moderator. Media buckets are private, and short-lived signed access respects approval, ownership and suspension. This is a conservative moderation policy suitable for an early community; no paid automated classifier or imaginary moderation team is assumed. Keep evidence and open gates in this directory.

Implementation/local evidence is recorded in `docs/VERIFICATION.md`; the requirement-by-requirement completion audit and external launch gates are in `docs/release/STATUS.md`. Checked work units certify only the specifically recorded coverage; hardware and real Facebook/Apple flows remain open.

On October 18, 2026 the user selected Facebook and Apple sign-in only and requested help creating a separate TikDog Meta app. Custom SMTP is no longer in the selected product scope.
