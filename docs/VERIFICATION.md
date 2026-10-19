# Verification — October 18, 2026

This report describes the App Store preparation work, including the final safety and foreground-refresh fixes. Branding is unchanged. **Local checks and the hosted backend smoke test passed; submission readiness remains unverified.** The external requirements are recorded in [release status](release/STATUS.md).

Subsequent product polish, regression evidence, and current follow-up checks are recorded in [the polish run](POLISH.md).

The latest October 19 continuation is recorded in [morning polish](MORNING-POLISH.md), including the complete combined run, final-source follow-ups and retained screenshots. The dated results below remain the earlier preparation baseline.

Built locally with Xcode 27.1 and Swift 6 language mode with complete concurrency checking. Minimum deployment target: iOS 17.0.

## Verified checks

| Check | Actual result | Evidence under `.build-artifacts/` |
| --- | --- | --- |
| Swift package behavior and transport tests | **26 passed** | `social-core-tests.log` |
| PostgreSQL 17 migrations, RPCs and authorization | **Passed**, using an isolated temporary database | `release-database.log` |
| Apple credential, account deletion and video deletion Edge behavior | **11 passed**, using local cryptography and mocked upstream HTTP | `release-edge-tests.log` |
| Release configuration/archive gate behavior | **6 passed**; repeated successfully after scheduled resumption | `release-gate-tests.log`; `python3 scripts/test_release_gate.py` |
| iPhone 15 Pro / iOS 17.0 full Debug UI suite | **9 passed, 0 failures** | `Safety-Complete-iOS17.xcresult`, `release-ui-complete17.log` |
| iPhone 17 Pro / iOS 26.5 full Debug UI suite | **9 passed, 0 failures** | `Safety-Complete-iOS26.xcresult`, `release-ui-complete26.log` |
| Post-change foreground/report checks on iOS 17 | **2 passed** | `Safety-Foreground-iOS17.xcresult`, `release-foreground17.log` |
| Post-change foreground/policy checks on iOS 26.5 | **2 passed** | `Safety-Foreground-iOS26.xcresult`, `release-foreground26.log` |
| Release simulator rejects offline-demo launch arguments when unconfigured | **1 passed**; no community tabs exposed | `Safety-Release-Visual.xcresult`, `release-no-demo-visual.log` |
| iPhoneOS Release compilation | **BUILD SUCCEEDED**, code signing disabled | `social-device-release.log` |
| Real archive with current missing launch configuration | **Rejected as intended** by the release-check build phase | `release-archive-final.log` |
| Hosted Supabase Auth/Storage/moderation/reporting/account deletion | **14 passed**, with disposable accounts and actual media bytes | `live-smoke.json`, `hosted-smoke-run.log` |
| Facebook provider configuration and authorization entry | Supabase enabled; correct Meta App ID/callback; real Facebook consent page reached, without granting access | `facebook-provider-status.json`, `facebook-setup-evidence.json` |
| Hosted native redirect configuration | Social callback added while preserving existing providers during setup | `social-callback-additive-push.json` |
| Connected native social-only sign-in UI | **1 passed on each of iOS 17 and 26.5**: both providers present, consent required, no email/password/reset controls | `SocialLogin-iOS17.xcresult`, `SocialLogin-iOS26.xcresult` |
| Hosted 90-day audit retention | Daily job active; real scheduler command succeeded; verification job removed itself | `hosted-retention-setup.json`, `hosted-retention-run.json`, `hosted-final-state.json` |
| Native client with hosted configuration | **BUILD SUCCEEDED**; built URL/public key inspected; live empty guest feed visually verified on iOS 17 | `hosted-client-build.log`, `hosted-guest-ios17.png` |
| Edge entry points and operator/live-smoke tools | **Deno type checking passed** | `release-deno.log` |
| Project generator | Regeneration produced identical project hashes | `project-before.sha`, `project-after.sha` |
| Resource manifests | Info.plist, privacy manifest and entitlements passed `plutil -lint` | Resource files in `TikDog/Resources/` |

The full Debug suites preceded the final foreground-refresh, unavailable-screen and social-login adjustments. The dedicated follow-up runs exercise those changed behaviors. The Release-only test is skipped in Debug and run separately with Release; its existence does not mean a hosted release was tested.

## Behaviors exercised

- Bundled dog footage plays through AVPlayer. Swiping selects another video; Following loads followed dogs. Center taps pause and resume, including when a loading spinner is present. A paused video stays paused across background/foreground refresh.
- Likes, bookmarks and comments update. Pending comments show review status. Comment reporting hides the comment; blocking its author removes the author's comments, and Settings supports unblocking.
- Search, daily voting, profile editing and a discovered dog's full-screen gallery work in the simulator.
- A bundled upload runs the actual trim/export/thumbnail/copy flow, appears in the owner's gallery as **In review**, and stays out of the public feed. The demo does not claim to operate a real moderation team.
- Native privacy and support documents open from Settings. Public operator fields are intentionally unconfigured at the user's request. Release archiving rejects this state.
- A Release app launched with `--demo --reset-demo` renders a readable unavailable screen rather than an offline community when backend configuration is absent. That screen was visually inspected after fixing its light/dark contrast.

## Authorization and failure coverage

The PostgreSQL harness applies all four real migrations with minimal fixtures for Supabase-owned `auth` and `storage` schemas. It exercises guest, authenticated and service roles. It proves pending profile/video/comment quarantine, private object metadata access, moderator authorization and audit recording, rejection of client approval forgery, stale profile revision rejection, immutable referenced media, report/block/unblock behavior, current terms acceptance, Apple credential vault permissions, suspension, and posting/storage rejection after account deletion starts. Earlier checks still cover ownership, private bookmarks, counters, pagination and one vote per day.

Swift transport fixtures cover guest publishable-key headers, expiring private-media URL hydration without changing canonical paths, expired session refresh, Facebook S256 PKCE exchange, callback validation, single-use/replay rejection, superseded/canceled attempts and sign-out invalidation, local sign-out despite failed remote logout, server-key rejection, and discarding an in-flight member response after sign-out. Demo persistence tests cover pending contributions, reports, blocked accounts and deletion behavior.

Edge tests verify actual local JWT signing/verification and reject a mismatched Apple subject/audience. Mocked HTTP responses cover failed Apple code exchange/revocation, deletion ordering (freeze → revoke → remove bytes → delete identity), missing legacy Apple credentials, storage failures, email-only accounts, video ownership and retry behavior, and requests lacking bearer authentication. **These tests do not contact Apple or hosted Supabase.**

Release-gate tests use isolated temporary fixtures. They reject missing identity, stale generated policies, accidentally embedded server credentials, mismatched backend evidence and truthy strings used instead of boolean pass values. A complete matching synthetic fixture passes the gate, proving it can accept a correctly configured state; it is not real launch evidence.

## Reproduce

```sh
scripts/verify_release.sh --skip-ui
scripts/verify_release.sh
```

The second command also runs native and UI tests on an installed iPhone simulator, preferring a booted device and then the newest installed iOS runtime. Override `TIKDOG_TEST_DESTINATION` for a specific destination. Logs are written under `.build-artifacts/`. A successful local test run can still end with a **publication BLOCKED** message; inspect `release-preflight.log` for the outstanding external setup.

Run the Release-only configuration check separately:

```sh
xcodebuild -project TikDog.xcodeproj -scheme TikDog -configuration Release \
  -destination "$(python3 scripts/simulator_destination.py)" \
  -derivedDataPath .build-artifacts/PolishReleaseFixture \
  -only-testing:TikDogUITests/TikDogUITests/testReleaseConfigurationNeverBecomesDemo \
  SUPABASE_URL= SUPABASE_PUBLISHABLE_KEY= ENABLE_TESTABILITY=YES \
  CODE_SIGNING_ALLOWED=NO test
```

This isolated build overrides backend settings to empty values without editing the configured app or deployment. Testability permits the native test bundle to compile against the Release app; optimization and the Release exclusion of demo launch arguments remain enabled.

## Artifacts and coverage limits

The current runnable Debug app is `ReleaseSafety/Build/Products/Debug-iphonesimulator/TikDog.app`; the unsigned device Release app is `ReleaseSafetyDevice/Build/Products/Release-iphoneos/TikDog.app`, both under `.build-artifacts/`. The final unavailable-screen image is `release-visual-final/54EEA00B-0ED5-484F-A67A-7E606133E600.png`. Existing screenshots in `docs/screenshots/` illustrate the demo, not a deployed community.

The linked hosted project `scgoiuhfnhpuhftgmegx` has all four migrations and three active Edge Functions. The native public key matches that project. `scripts/live_smoke.ts` passed 14 real hosted checks: admin-issued disposable test-token sign-in and terms acceptance, pending dog/video/comment quarantine, private object access and original video-byte delivery, moderator approvals/hiding, comment reporting, and deployed account deletion with video cleanup. A final database query found no remaining disposable smoke accounts or media objects. A fresh native Debug build opened the live empty guest feed on the iOS 17 simulator without an error alert. This is guest UI evidence, not a physical-device upload or Apple test.

The user selected Facebook and Apple only. Native email/password signup, sign-in and recovery were removed, along with their templates. SMTP is no longer required. The social callback is configured. Existing hosted email settings remain available only during provider setup; automatic approval review rejected disabling them before replacements were configured because of lockout risk. The final cutover is prepared separately. The smoke harness uses admin-created identities and admin-issued verification tokens without passwords or sent email; it does not claim a real Facebook login. Facebook is now enabled with the configured TikDog Meta app and minimum permissions; a real browser request reaches its Facebook consent page, where Login Review is still required. This does not prove completed login, code exchange or Facebook-linked account deletion. The hosted Apple provider is disabled, so real Apple authorization/revocation remains unverified. Server test credentials were retrieved through the authenticated CLI and passed only in memory to the harness; no server key was placed in native configuration.

After explicit user approval, Supabase Cron was enabled and the daily `tikdog-audit-retention` job was installed for 03:00 UTC. A temporary scheduler job executed the same 90-day deletion command successfully and removed itself. The final job state and execution logs are retained; this proves execution now, not future scheduler uptime.

The attempted complete local Supabase stack failed when Docker's VM encountered disk I/O/read-only filesystem errors and the Mac was almost out of free space. Only rebuildable project caches were reclaimed; no Docker data was deleted. The database fixture checks do not emulate Supabase Auth, Storage, gateways or SMTP.

The user deferred public operator/contact/domain details and does not have a paid Apple Developer membership. Published policy/support pages, moderation staffing, real Facebook/Apple sign-in and deletion/revocation, final social-only provider cutover, camera/microphone permission behavior, signed physical-device installation, TestFlight and App Store Connect metadata remain open. Apple token revocation **is implemented**, but its real-provider behavior is not yet verified. Push delivery is outside the current product scope. No performance benchmark or App Store approval is claimed.
