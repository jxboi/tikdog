# Runtime and backend contracts

The SwiftUI views use the main-actor `AppModel` for shared dog/video state and feed pagination, `CommentsViewModel` for comment loading/sending, and `UploadViewModel` for the import/export/upload lifecycle. The selected own dog lives in `AppModel` for the current account session so Profile and upload defaults agree. `PlaybackController` owns a bounded pool of AVQueuePlayers and their AVPlayerLoopers. A separate `TikDogCore` package contains Codable/Sendable models and the repositories so data behavior can be tested without UIKit.

Both repository actors implement `TikDogRepository`. In Debug, missing configuration selects `DemoRepository`; Release shows an unavailable screen instead. Valid HTTPS/public-key configuration selects `SupabaseRepository`. There is no automatic switch from a failing live backend to fake demo data. The demo persists a JSON snapshot and copies imported files to app Documents. The live repository uses URLSession for GoTrue auth, PostgREST RPC, and streaming Storage uploads. Sessions are stored in the iOS Keychain, never UserDefaults.

## RPC surface

| Function | Access | Result |
| --- | --- | --- |
| `bootstrap` | Guest / member | Initial dogs/videos, private viewer state, activity, vote standings |
| `get_feed` | Guest / member | Eight videos, joined dog metadata, next offset |
| `discover_dogs` | Guest / member | Bounded name/breed matches, with smaller creators first |
| `dog_profile` | Guest / member | Visible dog and video gallery |
| `get_comments` | Guest / member | Latest 100 comments with public display names |
| `save_dog` | Owner | Pending profile; content revision increments on edits |
| `publish_video` | Owner | Pending video after validating owned canonical Storage paths |
| `set_like`, `set_bookmark`, `set_follow` | Member | Idempotent desired-state change |
| `add_comment` | Member | Pending comment, visible only to its author until approval |
| `cast_daily_vote` | Member | Updated standings; unique user/day prevents double votes |
| `report_video`, `report_content`, `block_owner`, `unblock_owner`, `blocked_accounts`, `read_activity` | Member | Reporting, reciprocal blocking, unblock management, activity |
| `accept_terms`, `account_state` | Member | Versioned age/terms consent and account state |
| `moderation_queue`, `moderate_content`, `prune_moderation_audit` | Protected moderator / service | Review, audited approval/removal/suspension, retention |
| `begin_account_deletion`, `store_apple_credentials`, `apple_credentials_for_deletion` | Service only | Freeze writes and handle private Apple credentials |

Application RPC inputs are strings so encoding does not depend on implicit JSON scalar coercions. SQL validates/casts at the boundary. Outbound Codable models use snake_case keys and ISO 8601 timestamps. Errors remain visible to the caller; optimistic likes are rolled back on failure.

The authenticated Apple-credential and two deletion Edge Functions handle Storage bytes and auth administration. Every request verifies its bearer token; deleting a video additionally verifies its dog's owner. These functions require the server-side service role key. Account deletion freezes contribution/storage commits under a database row lock, revokes Apple authorization, removes bucket bytes, then deletes the identity. Storage/account deletion is retryable, but the Storage API and PostgreSQL are separate systems, so a failure between steps can temporarily leave a missing media file with a database row. An operational cleanup job can reconcile orphaned media for a larger deployment.

## Authorization

- All application tables enable RLS. Guests can browse visible profiles/videos/comments and aggregate standings.
- Bookmarks, reports, block lists, votes, and notifications are private to the authenticated actor. Guests have read grants on these tables so shared RPCs can execute, but no matching RLS policies, so they read zero rows.
- Only owners can edit dog identity. Column grants prevent forging owner IDs, featured badges, and counts.
- Interaction triggers update counters and emit notifications. Clients cannot write notifications directly.
- Security-definer functions have empty search paths, qualified names, and explicit actor checks. Default PUBLIC function execution is revoked and replaced with an allowlist.
- Reports can target videos, comments and profiles and hide the target for the reporter. Only authorized moderators can approve or hide content; profile approval requires the revision actually inspected.
- Blocks apply reciprocally to app queries and sever follow relationships in both directions. Storage is private. SELECT policies allow approved public content, owner previews and authorized moderators. Signed playback URLs expire after 15 minutes. Referenced objects cannot be replaced through delete/reinsert.

## Lifecycle

Only the visible feed page plays. The previous page and two following pages remain prepared; everything else is released. Scrolling resets the new video's pause state. Explicit pause is respected after a sheet closes or the app returns to the foreground. Comments, profiles, auth, uploads, and app backgrounding suspend playback. Looper references remain alive for each pooled player and time/KVO observations are removed when switching or stopping.

Upload stages are choose → edit → export → upload → success. The file importer copies its temporary representation. AVAssetExportSession exports only the selected time range, and an image generator makes the cover from the resulting clip. The final upload streams from disk. Failed publishing preserves the draft and compensates for completed Storage writes. Successful demo media moves into durable Documents storage before temporary exports are removed.


## Release boundaries

Canonical `storage://` paths stay in saved content. Transient signed playback/avatar/thumbnail URLs are resolved through the Storage API. Bootstrap and foreground/periodic refresh renew these URLs, including any open remote profile. Profile refresh replaces that gallery rather than retaining rows removed by moderation. Data epochs discard superseded reads; separate session epochs discard writes completed after account changes without dropping successful writes during ordinary refresh. The state revision advances after local writes and full snapshot replacements, preventing older feed/profile reads from overwriting either. A full refresh retries once if a write supersedes it; further writes retain the local state until a later refresh. Feed/profile requests fetch again when a changed revision invalidates their result, retaining request ownership until a valid response, cancellation, supersession, epoch change or failure. A committed full refresh supersedes pending feed requests and their failures. The visible feed reevaluates pagination after refresh/page completion and when uncovered or foregrounded. Recorded failures require explicit retry. Search restarts when its query, data epoch or state revision changes. Read-only catalog hydration does not advance the state revision. Repository session generations discard late network responses after sign-out or account changes. Local sign-out clears credentials even when remote logout fails.

Apple native sign-in uses a hashed nonce and Supabase ID-token authentication, then sends the one-time authorization code to an authenticated server function. That function verifies Apple's identity signature, audience and subject, exchanges the code and stores the refresh credential in a private schema. Only the deletion service can retrieve it; the iPhone never receives the Apple refresh token. Frozen/suspended accounts can repair verified authorization to complete deletion.

After confirmed account deletion, `AppModel` clears private catalog/selection state and invalidates the session before loading the guest feed. An offline guest refresh therefore cannot leave the deleted account visible, and older write completions cannot restore it. A failed deletion retains the account state so the user can retry.

Authentication is Facebook and Apple only. Facebook uses ASWebAuthenticationSession and Supabase OAuth with an in-memory 256-bit PKCE verifier, exact native callback validation, a one-time code exchange, cancellation and session-generation checks. The app never accepts tokens from a URL fragment and does not contain email/password signup or recovery code. Provider passwords stay with Facebook/Apple; Supabase manages application identities and sessions. Website/native legal content is generated from a single source, and archives are blocked without deployment identity, current policy checks, live backend evidence, signing and device verification. See `docs/release/` for evidence and unresolved external launch requirements.
