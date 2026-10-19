# App Store submission preparation

## Configure public identity

Fill `release/config.json` with the real operator name, support email, website and policy/support page URLs, and moderation owner. The user has explicitly deferred these details. Do not invent them. Keep the age and policy version aligned with server acceptance and app copy.

Run `python3 scripts/prepare_release.py`, publish `website/privacy.html`, `terms.html`, and `support.html` at those URLs, and run `python3 scripts/check_release.py --online`. Generated native policies and website policies share `release/legal.json`. Review the text against the actual hosting region, providers, retention settings, and operator obligations before publishing. `Config/Release.xcconfig` contains public settings only.

Configure Supabase in ignored `Config/Secrets.xcconfig` using `Secrets.example.xcconfig`. Use a publishable or anon key, never a server key. Missing backend settings show an unavailable screen in Release; only Debug supports the local demo and `--demo`. Archiving runs a mandatory release configuration/evidence check and fails while launch requirements remain open.

## App Store Connect

Suggested description:

> TikDog is a community for dogs and their people. Discover short dog videos, follow your favorite pups, create profiles for your own pack, and share everyday adventures. New contributions are reviewed before appearing publicly. Report unsafe content, block accounts, manage your saved videos, and delete your account inside Settings.

Set the support URL and privacy policy URL to the published pages. Provide screenshots captured from the actual final release build using licensed/approved content. Do not show fictional engagement as a live community. Complete the current age-rating questionnaire accurately for user contributions, messaging/comments, moderation and intended audience; the product requires users to attest they are 16 or older and is not designed for the Kids Category. Let Apple's current questionnaire determine the store rating.

Privacy labels should describe the deployed app, independently of the bundled privacy manifest. Review at least: name, email address, user ID, photos/videos, audio in user videos, other user content (comments/reports/profiles), and product interaction (likes/follows/votes). These are linked to the account and used for app functionality, and engagement also drives product personalization. No advertising, tracking, location or contacts collection is implemented. Review service-provider logs and any added SDKs before completing the answers. Do not claim no data collected because the demo is offline.

No paid features or external checkout are currently implemented. If monetization is added, reassess Apple's payment rules before submission.

## Review access and notes

Provide a reviewer access procedure supported by the configured Facebook/Apple login flows; verify it with a reviewer who has no app role before submission. Do not invent an email/password login that the app does not offer or share a personal provider password. Record any dedicated approved review/test-account instructions in App Store Connect. Keep the backend online, allow reviewers to create an account with the supported providers, accept terms, create a dog and submit content through normal moderation. Do not ask reviewers to connect a backend or run project setup.

Suggested review notes, after replacing the account fields in App Store Connect:

> TikDog is a native dog-video community. Guests can browse approved videos and profiles. Sign in with Facebook or Apple to upload, comment, follow or vote. Each owner can create multiple dog profiles. Contributions await human approval; pending items remain visible to their owner in Profile and do not appear in public discovery. Video/profile/comment options include reporting and account blocking. Manage blocked accounts and initiate permanent account deletion in Profile > Settings. Deleting an Apple-linked account revokes Apple authorization and removes uploaded media and account content. Privacy, terms and support are available in Settings and at the submitted URLs. Daily voting resets at 00:00 UTC. No purchase is needed.

## Required launch evidence

Use ignored `release/live-evidence.json` to record checks incrementally; set each `passed` value true only after that specific check has actually passed. The current file records hosted backend and retention results, and keeps the other checks false. Keep artifacts with the evidence pointers; a checkbox is not test proof. Record the exact archive `backend_url` and `bundle_id`. The archive also requires `.build-artifacts/live-smoke.json` for that backend and a successful `--online` policy check less than seven days old. Update `config_sha256` using `shasum -a 256 release/config.json`. Attach the successful live smoke output, real Facebook sign-in/cancellation/deletion and final social-only provider settings, physical-device permission/camera results, Apple sign-in/deletion/revocation observations, TestFlight installation, the moderator rota and the verified retention job. Then archive with the Apple team and production backend settings.

The current user does not have a paid Apple Developer membership. Enroll before App Store signing and TestFlight. A local unsigned device build is useful compile evidence but cannot prove a signed device flow or submission eligibility. No App Store approval is guaranteed by passing these checks.
