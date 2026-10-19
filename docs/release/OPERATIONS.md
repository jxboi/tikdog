# TikDog moderation and release operations

All uploads, comments, and dog profile changes wait for human approval. No automated safety classifier or push notification service is assumed. Approval of a video also requires its dog's profile to be approved before it can appear publicly.

## Staff the queue before opening registration

Name a primary moderator and a backup in your operating procedures. Set the primary in `release/config.json`. Review the queue at least daily and respond to urgent animal harm promptly. The published commitment is to review reports within 24 hours. The CLI exits with status 2 when an open report is overdue, so an operator's job runner can alert on it. This repository does not send email or notifications to a fictional moderation team.

Use Deno and server credentials from your secret manager. Never put a service key in an iPhone config, website, screenshot, or source file. The CLI authenticates as the service role; it is an operator tool, not a public website. An operator can instead be added by an administrator to `private.moderators` and use authenticated RPCs with their account JWT. User-editable metadata never grants moderation access.

```sh
# Export SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY securely.
deno run --allow-env --allow-net --allow-read scripts/moderate.ts queue > /tmp/tikdog-review.json
deno run --allow-env --allow-net --allow-read scripts/moderate.ts inspect dog DOG_UUID
deno run --allow-env --allow-net --allow-read scripts/moderate.ts review dog DOG_UUID approve --revision 1 --note 'Inspected name, bio and photo; no unsafe content'
deno run --allow-env --allow-net --allow-read scripts/moderate.ts inspect video VIDEO_UUID
deno run --allow-env --allow-net --allow-read scripts/moderate.ts review video VIDEO_UUID approve --note 'Watched full clip and checked caption, tags and sound'
deno run --allow-env --allow-net --allow-read scripts/moderate.ts review comment COMMENT_UUID approve --note 'Reviewed full comment'
```

The queue/inspect output includes media links that expire after 15 minutes. Treat this file as private and delete it after review. Watch the full clip with sound, inspect its caption/tags and linked profile, and check for cruelty, dangerous handling, sexual content, hate, personal information, harassment, spam and missing rights. Inspect photos and profile text too. A profile edit increments its revision; approval with a stale revision fails. Inspect it again before retrying. Never approve by ID without looking at the content.

## Handle reports and appeals

`queue` returns unreviewed contributions and open reports. Use `inspect report REPORT_UUID`, then inspect its `video_id`, `comment_id`, or `dog_id` even if it was previously approved. Confirm the report and hide unsafe material, or dismiss a report with a reason. Suspending an account immediately removes its profiles and content from queries and new media signing and blocks contributions. Restoration is an explicit decision.

```sh
deno run --allow-env --allow-net --allow-read scripts/moderate.ts review video VIDEO_UUID hide --note 'Animal handling violates community rules'
deno run --allow-env --allow-net --allow-read scripts/moderate.ts review account USER_UUID suspend --note 'Repeated unsafe contributions'
deno run --allow-env --allow-net --allow-read scripts/moderate.ts review report REPORT_UUID dismiss --note 'Inspected content and found no violation'
```

Every decision writes `public.moderation_actions`. A content decision resolves reports for that target. Hiding blocks new access links immediately. Already issued links expire within 15 minutes; downloaded or shared copies cannot be recalled. Media objects referenced by content cannot be deleted/reinserted by clients to bypass review. Account/video deletion goes through authenticated Edge Functions, which remove actual object bytes.

Offer an appeal through the real support email. Record a new decision with its reason when restoring content or an account. Do not place sensitive personal data in audit notes.

## Audit retention

Run `scripts/moderate.ts maintenance` daily through your operator's scheduler, or enable Supabase Cron and schedule the owner-run job below. The current linked project has the explicitly user-approved daily job installed; a real scheduler execution succeeded on October 18, 2026. See `.build-artifacts/hosted-retention-run.json`. Reapply the reviewed SQL to another project only with authorization for the recurring deletion:

```sh
npx supabase db query --linked --file supabase/operations/audit_retention.sql
```

Verify the job exists and completes before recording `audit_retention_job` in release evidence. The migration supplies the pruning function; the separate hosted setup enables Cron. See [Supabase Cron setup](https://supabase.com/docs/guides/cron/quickstart). Moderation records contain identifiers and action/reason, never copies of video or comment text; account content deletion still cascades immediately. Configure hosting log/backup retention and confirm the policy describes the actual deployment.

## Deploy the backend

```sh
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push
npx supabase functions deploy apple-credentials
npx supabase functions deploy delete-account
npx supabase functions deploy delete-video
```

All three functions verify the bearer token with Supabase Auth. `verify_jwt=false` disables only the legacy gateway verifier. New objects require current terms acceptance. Existing content is quarantined by migration 004, and old backend public paths are converted to canonical paths. Review existing content before reopening a migrated service; check any previous public caches separately.

Enable Sign in with Apple for the actual bundle ID in Apple Developer and Supabase Auth. Set the Edge Function secrets from `supabase/.env.example`: native bundle ID, Apple team ID, key ID and the private `.p8` key. The Edge Function makes its own short-lived client secret, exchanges the one-time authorization code, verifies Apple's identity signature/audience/subject against the signed-in Supabase identity, and keeps the refresh token in a private server table. It never returns that credential to the app. Rotate keys in your secret manager and verify sign-in/revocation again after rotation.

Native Apple sign-in continues to use the nonce-protected Supabase ID-token flow. Registering the authorization code is a second authenticated step so deletion can revoke Apple later. Legacy/missing credentials cause a clear reauthorization request before the account is frozen. A revocation/storage failure retains the identity and frozen state for retry; even frozen/suspended users can repair verified Apple credentials and delete their account.

The user selected Facebook and Apple only. See [social sign-in setup](SOCIAL_LOGIN.md). There is no native email/password signup, sign-in or recovery flow, so SMTP and native email templates are not launch requirements. Keep the existing hosted provider available during setup; the reviewed additive config in `supabase/operations/native-auth` adds the social callback without removing current redirects. Only after both replacement providers work, preview and apply `supabase/operations/social-only` to disable the email provider and remove obsolete redirects. Automatic approval review rejected doing this cutover before replacements were configured because of lockout risk. Never push the full local-development config to production.

## Live smoke verification

Use an isolated staging project containing migrations and deployed functions. The harness creates two disposable identities with synthetic email identifiers and admin-issued verification tokens (no passwords or sent messages), uploads the bundled licensed fixture, checks private/public access, moderation, comment reporting and account/media deletion, and removes its test objects and accounts. This verifies the managed backend independently of Facebook/Apple. It does not prove either social-provider login flow.

```sh
# Securely export SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_PUBLISHABLE_KEY.
TIKDOG_SMOKE_ALLOW_WRITE=YES deno run --allow-env --allow-net --allow-read --allow-write scripts/live_smoke.ts
```

Successful evidence is written to `.build-artifacts/live-smoke.json`. The harness passed all 14 checks against the current linked project on October 18, 2026, and its disposable accounts/media were cleaned up. Keep `.build-artifacts/live-smoke.json` with the release evidence. Re-run after backend changes; this does not verify Facebook/Apple login or provider-specific deletion.
