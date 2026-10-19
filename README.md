# TikDog 🐾

A native iPhone video community where the dogs have the profiles. Swift 6, SwiftUI, AVPlayer, Swift Concurrency, and Supabase. iOS 17 or later.

## Run it now

1. Open `TikDog.xcodeproj` in Xcode 16 or newer (Swift 6 required).
2. Select the **TikDog** scheme and an iPhone simulator.
3. Run. No credentials, package downloads, or third-party project generator are required.

Debug builds automatically start in **demo mode** when Supabase configuration is absent. Cabby, Mochi, Milo, and Luna have bundled, licensed videos, so the feed works offline. The demo signs you in locally as Cabby's person. Likes, follows, comments, bookmarks, dog profiles, daily votes, and uploaded videos persist on this device. Demo accounts and engagement are fictional. Release builds require backend configuration and never fall back to demo mode.

Try the **+** tab → **Try with a demo clip** → add a caption → **Let them shine**. This runs the real trim, H.264 export, thumbnail generation, persistence, and playback flow without a backend.

Debug launch arguments:

- `--demo`: force the offline repository even when credentials exist.
- `--demo --reset-demo`: reset only TikDog's demo data and uploaded media before launching.

Simulator previews: [Feed](docs/screenshots/01-Feed.png) · [Discover](docs/screenshots/02-Discover.png) · [Profile](docs/screenshots/03-Profile.png) · [Upload](docs/screenshots/04-Upload.png)

The latest local improvements and checks are recorded in [morning polish](docs/MORNING-POLISH.md). Debug and Release builds treat Swift warnings as errors.

## Implemented

- Edge-to-edge, vertically paged For You and Following feeds, looped AVQueuePlayer playback, tap to pause, double-tap heart animation, mute, playback progress, retry UI, and a bounded four-player preload window. Playback suspends for backgrounding and covering screens.
- Dog avatars, names, captions, hashtags, follows, likes, comment sheets, bookmarks, and the native share sheet. Sharing sends the actual video file/URL; it doesn't depend on an undeployed website.
- Multiple dogs per owner, creation and editing with photo selection, breed, birthday, bio, counts, video galleries, and private saved collections. The selected dog stays consistent across Profile and upload defaults for the current account session.
- Camera recording, PhotosPicker import, start/end trimming to 1–60 seconds, preview, 720p export, generated JPEG thumbnail, streamed file upload progress, retained draft on failure, and retry. The publish confirmation opens the uploaded dog's gallery.
- Name/breed search, trending tags, community profiles, a smaller-creator discovery boost, daily UTC voting, and historical daily-winner rankings.
- Facebook browser sign-in with PKCE, native Sign in with Apple with a cryptographic nonce, Keychain session persistence, and coordinated access-token refresh. TikDog does not collect passwords.
- In-app activity; video/comment/profile reporting, reciprocal blocking and unblock management; permanent video/account deletion with a server write freeze and Storage byte cleanup.
- Human approval before videos, comments, and profile changes appear publicly; private media with 15-minute access links; a moderator queue/CLI with revision checks and an audit trail.
- Versioned terms and age consent, shared native/web privacy/terms/support source, Facebook/Apple-only authentication, and server-side Apple token exchange/revocation.
- Guest backend browsing. Account creation is requested for social writes, uploads, and voting.
- RLS on every application table, narrow column grants, server-controlled counters/badges, indexed feeds, bounded queries, immutable storage objects, and ownership checks before publishing or deleting.

## Connect Supabase

### 1. Create and migrate the backend

Create a Supabase project. Install the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started), then run from the repository root:

```sh
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
supabase functions deploy apple-credentials
supabase functions deploy delete-account
supabase functions deploy delete-video
```

The migrations create all tables, RLS policies, RPC functions, triggers, indexes, and three private media buckets. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided automatically to hosted Edge Functions. **Never put the service role key in the iOS app.**

The two deletion functions validate the bearer token with `auth.getUser()` themselves. The checked-in `verify_jwt = false` disables the legacy gateway verifier so current Supabase signing keys work; it does not disable authentication in the functions. Client-supplied owner IDs are never trusted.

### 2. Configure the app

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

Edit the ignored file:

```xcconfig
SUPABASE_URL = https:/$()/YOUR_PROJECT.supabase.co
SUPABASE_PUBLISHABLE_KEY = YOUR_PUBLISHABLE_OR_ANON_KEY
```

Keep `https:/$()/` exactly as shown: Xcode treats a literal `//` as a comment. The build expands this to `https://`. Both current publishable keys and legacy anon JWT keys are supported. Only this public client key belongs in the app.

Rebuild. The app now uses Supabase exclusively and starts as a guest. A new backend begins empty; configure Facebook and Apple, sign in with one of those providers, add a dog in Profile, and upload a clip. Local demo content and interactions are never sent to a live project.

### 3. Authentication

- Configure a dedicated TikDog Meta app and the Facebook provider in Supabase. Facebook Login requires the `email` permission and the hosted callback `https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback`. The native redirect is `tikdog://auth/callback`. Keep the Meta App Secret in Supabase only. See [social sign-in setup](docs/release/SOCIAL_LOGIN.md). Email/password UI and password recovery are removed; custom SMTP is not required for the selected product.
- For Apple, register your bundle identifier in your Apple Developer account and enable **Sign in with Apple**. Select your signing team in Xcode and use the same identifier in Supabase's [Apple provider configuration](https://supabase.com/docs/guides/auth/social-login/auth-apple). The device entitlement is included. Test on a physical iPhone signed into iCloud.
- Set `PRODUCT_BUNDLE_IDENTIFIER` in `Config/App.xcconfig` if your team uses a different identifier. The demo and simulator builds need no paid signing team.

### 4. Release safety and operations

All media buckets are private. Contributions wait for moderator approval, including dog photos, names and bios. The app signs authorized media for 15 minutes; pending content is visible only to its owner and moderators. Reports hide content for the reporter, blocking applies in both directions, and clients cannot replace approved bytes at an existing object path.

Read [moderation and backend operations](docs/release/OPERATIONS.md) for deployment, Apple's server secrets, social providers, moderation review, suspension, retention, and the real-service smoke harness. The server key stays out of the app.

Read [submission preparation](docs/release/SUBMISSION.md) for operator details, policy publishing, privacy labels, reviewer access, signing and launch evidence. Branding is unchanged. The user has deferred public operator details and does not yet have paid Apple Developer membership. Release preparation is not a claim that these external launch requirements are complete.

Debug keeps the offline demo. A Release build without backend configuration shows an unavailable screen; `--demo` does not enable demo mode in Release. Archiving fails while required release configuration or launch evidence is missing.

## Architecture

```text
TikDog/
  App/          SwiftUI lifecycle, tab shell, observable application view model
  Features/     Feed, profiles, upload, discovery, voting, activity, auth
  Services/     AVPlayer pool and Keychain session storage
  Design/       Native type, color, avatar, and button components
  Resources/    Four offline clips, thumbnails, icon, privacy manifest
TikDogCore/
  Sources/      Sendable domain models, validation, ranking, repository protocol
                Persistent demo actor and URLSession Supabase actor
  Tests/        Domain, persistence, authorization, and HTTP transport tests
supabase/
  migrations/   Schema, RLS, query API, counters, notifications, media policies
  functions/    Authenticated storage-aware account/video deletion
TikDogUITests/  Real simulator interaction and screenshot tests
TikDogTests/    Native state, request-ordering, and real-media lifecycle tests
scripts/       Reproducible project/icon generation and isolated database tests
```

The UI uses MVVM with `@Observable` models on the main actor. Both repositories conform to the same async, Sendable protocol. AVFoundation objects stay on the main actor; HTTP, storage, and persisted demo state live behind repository actors. Uploads stream from files rather than loading full movies into memory.

The backend uses Supabase's Auth, PostgREST RPC, and Storage HTTP APIs through URLSession, avoiding a third-party iOS SDK dependency. The local core package resolves without the network. The tiny Edge Functions pin Supabase JS and Zod dependencies.

### Feed ranking and pagination

The For You score combines likes, weighted comments, view count, and time decay. Dogs with fewer than 1,000 followers receive a 1.4× discovery multiplier. Following is newest-first and follows **dog IDs**. Stable ID tie-breaking and offset/limit pagination fetch eight clips at a time; the app deduplicates overlapping pages. Profile galleries are bounded to 90 clips, comments to the newest 100, and activity to 100 items for this MVP. A large deployment should use ranking snapshots/cursors and add further gallery/comment pagination.

Daily voting has a database primary key on `(user_id, vote_day)`, which prevents concurrent duplicate votes. A completed UTC day's winner is derived from vote totals, with dog UUID as a deterministic tie-breaker; no scheduler is needed. Today's totals and historical wins are separate leaderboard views.

## Verify

Core tests run on macOS without a simulator:

```sh
swift test --package-path TikDogCore
```

Build and run native and UI tests on an installed simulator:

```sh
xcodebuild -project TikDog.xcodeproj -scheme TikDog \
  -destination "$(python3 scripts/simulator_destination.py)" \
  -derivedDataPath .build-artifacts/DerivedData \
  -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test
```

The UI suite launches isolated demo data, exercises likes, bookmarks, comments, search, voting, profile editing, and a full export/publish/gallery flow. It checks multi-dog creation and private review status, draft keep/discard choices, activity filters, accessible unread state and gallery playback. Screenshots remain available as XCTest attachments.

The same scheme runs native tests for feed catalog retention, moderation filtering, account/refresh request ordering, comment draft preservation and retry behavior, overlapping profile refreshes, upload file ownership, and playback continuity when media URLs renew. Delayed responses verify that completed writes survive, page loading continues and deleted-account content stays removed. Run just these faster app-state checks with `-only-testing:TikDogTests`.

`scripts/verify_release.sh` selects an installed iPhone simulator, preferring a booted device and the newest available iOS version. Set `TIKDOG_TEST_DESTINATION` to use a specific destination.

Database checks use an isolated temporary PostgreSQL 17 cluster and remove it when finished. They never connect to your existing databases:

```sh
# macOS, if needed: brew install postgresql@17
scripts/test_database.sh
# Elsewhere: TIKDOG_PG_BIN=/path/to/postgres/bin scripts/test_database.sh
```

This runs the actual migrations, RPCs, and RLS under `anon` and `authenticated` roles against small fixtures for Supabase-owned `auth`/`storage` schemas. It checks guest access, private bookmarks, ownership, forged counters/badges, idempotent likes, feed pagination, duplicate voting, storage paths, publication, notifications, reports, reciprocal blocking, and rejected uploads from deleted accounts. It does not emulate Supabase's gateway, email service, or Storage byte service.

Check deletion functions:

```sh
deno test --allow-env supabase/functions/_shared/*_test.ts
deno check supabase/functions/delete-account/index.ts supabase/functions/delete-video/index.ts supabase/functions/apple-credentials/index.ts scripts/moderate.ts scripts/live_smoke.ts
```

Regenerate the project after adding source files outside Xcode:

```sh
python3 scripts/generate_project.py
```

The checked-in project is ready to open; generation is optional. See [verification](docs/VERIFICATION.md) and [current polish evidence](docs/POLISH.md) for recorded checks, and `MEDIA_CREDITS.md` for source footage and licensing.

## Scope of this MVP

Real Facebook/Apple sign-in requires provider credentials and hardware verification. Hosted Auth/Storage/Edge Function smoke checks have passed against the linked project using disposable admin-issued test tokens; that is not real social-provider login proof. Camera capture also requires a physical device. The client, schema, RPCs, policies, and deployment instructions are implemented; local demo behavior and database authorization can be verified independently.

The app uses progressive MP4 delivery, in-app notifications refreshed when Activity opens, and basic aggregate engagement/recency ranking. Adaptive HLS transcoding, personalized watch-time learning, push delivery, universal-link web pages, offline backend-write queues, and a browser-based moderation console are outside this release. The included operator CLI handles review, reports, removals and suspension; Apple token revocation is implemented.
