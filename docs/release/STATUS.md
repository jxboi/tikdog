# Release status — October 18, 2026

**Not ready to submit yet.** The implementation and local checks are prepared; production identity, completed Facebook login/deletion proof, Apple provider setup and Apple enrollment remain open. The Supabase project is connected and the 14-check hosted backend smoke test passed. The user explicitly deferred operator/contact/domain details and does not have a paid Apple Developer account. Branding is unchanged.

The October 19 local continuation and its verification are recorded in [morning polish](../MORNING-POLISH.md). That session does not change the external launch requirements below.

October 19 follow-up: the regular daily retention job succeeded at 03:00 UTC (11:00 Singapore time), deleting zero expired rows. The read-only scheduler check is saved in `.build-artifacts/retention-daily-followup.json`. The expired October 18 one-time resume automation is now paused to prevent further repeat wake-ups; the release objective remains open.

| Requirement | Current evidence | Remaining launch requirement |
| --- | --- | --- |
| Filter objectionable contributions before publication | Videos, comments and profiles default to pending; only authorized moderators approve. PostgreSQL tests prove guest quarantine and prevent approval/media-replacement bypasses. Simulator uploads show review status. | Assign moderators and operate the queue, with a backup and 24-hour report response. |
| Reporting and blocking | Video/comment/profile reports, immediate viewer hiding, reciprocal blocking and unblock management pass database checks; comment reporting and block/unblock pass simulator flows. | Hosted comment reporting/hiding passed; verify the full moderation workflow with the assigned operators and record response procedures. |
| Privacy, terms and contact | Shared policy source generates native screens and three website pages; current terms/age acceptance is enforced by the server. The archive rejects unconfigured details. | Supply real operator/contact/URLs, confirm deployment-specific policy details, publish the pages and complete App Store privacy/age metadata. |
| Apple account deletion | Native authorization code goes to an authenticated Edge Function; signed Apple identity subject/audience are verified before retaining the server-only refresh token. Deletion freezes writes, revokes Apple, removes bytes and deletes the identity. Local cryptographic/failure tests pass. | The hosted Apple provider is currently disabled. Configure it and its server keys, then prove real sign-in, reauthorization and revocation on hardware. |
| Social authentication | Facebook PKCE and native Apple flows implemented; email/password and recovery code removed. All 26 Swift tests pass; the social-only screen and consent gating pass on iOS 17 and 26.5. Meta App 1422143516770927 and its required permissions/callback are configured; Supabase Facebook is enabled and the live flow reaches Facebook consent. | Complete real Facebook login/cancellation/deletion, Meta review/publication and Apple setup, then perform the verified provider cutover. SMTP is no longer required. |
| Data deletion | PostgreSQL rejects uploads/posts after deletion starts. Edge tests prove cleanup ordering, ownership, idempotent video retry and failure handling. | Hosted account/video-byte cleanup passed the live harness; real Apple-linked deletion still needs hardware/provider proof. |
| Production completeness | Unsigned device Release build succeeds. A separate Release simulator test proves missing configuration cannot expose demo content, including with `--demo`. Real archive refuses missing launch requirements. A fresh Debug build connects to the live backend and displays its empty guest feed. | Provide real reviewer access, complete signed device/TestFlight checks and retain matching deployment evidence. |
| Media/session refresh | Private media uses 15-minute signed URLs; canonical storage paths stay unchanged. Session generations discard stale network responses, and foreground refresh retains an open profile and a paused video. Local transport/foreground simulator checks pass. | Confirm signed media playback and refresh with the actual hosted project. |
| Audit retention | The user-approved daily job is active at 03:00 UTC; a real scheduler execution of its 90-day deletion command succeeded and the temporary verification job removed itself. | Monitor future scheduled runs and recheck after deployment changes. |
| Signing and submission | Build/archive checks and App Store review notes are supplied. | Paid Apple Developer enrollment, identifiers/capabilities, signing, TestFlight and App Store Connect setup. |

## Local evidence

The [verification report](../VERIFICATION.md) records commands, exact checks and coverage limits. All six release-gate tests passed again. The Supabase project `scgoiuhfnhpuhftgmegx` has all four migrations and three active Edge Functions; its public client key matches the native app configuration. `.build-artifacts/live-smoke.json` records 14 passed hosted checks. Disposable accounts and media were removed. `.build-artifacts/hosted-retention-run.json` records a successful scheduler execution; `.build-artifacts/hosted-guest-ios17.png` shows the native guest feed. `release/live-evidence.json` records only actual backend and retention successes; unverified Facebook, Apple, hardware and operational checks remain false. The earlier failed Docker startup remains historical evidence and is not needed for these hosted results.

## Files to use when the deferred setup is available

- `release/config.json`: real public identity, policy URLs and moderation owner.
- `release/legal.json`: reviewable shared policy source.
- `Config/Secrets.example.xcconfig`: public backend settings for the app.
- `supabase/.env.example`: server-only Apple credential settings.
- `docs/release/OPERATIONS.md`: backend, social providers, moderation and retention setup; live smoke command.
- `docs/release/SUBMISSION.md`: metadata, reviewer access and signing checks.
- `release/live-evidence.example.json`: record actual launch evidence after checks pass; never mark unrun checks passed.

The objective remains open until these launch requirements are true and verified. Passing local tests does not mean Apple has approved the app.
