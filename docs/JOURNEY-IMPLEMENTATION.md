# Journey implementation — 19 October 2026

The first-post flow now carries the user from sign-in through dog setup, video editing, submission, and review status. Viewers can continue browsing and interacting without creating a dog.

## Delivered

- Upload and Add Dog resume after successful authentication or terms acceptance. Canceling authentication clears the requested destination. Authentication reloads account state before dismissing.
- The sign-in screen reads provider availability from Supabase. Disabled providers remain unavailable with an explanation and failed availability checks offer retry. Apple setup itself remains deferred at the user's request.
- First-time posters see dog setup before the media picker. Dog creation distinguishes required name/breed from optional photo, birthday, and bio, with a direct **Save dog and continue** action. Existing owners proceed to video selection.
- Upload drafts retain the clip, submission identity, selected dog, trim positions, caption, and tags in private account-specific application storage. Files are protected on device and excluded from backups. **Save draft and close**, **Continue draft**, and confirmed discard are available. Successful submission and account deletion remove the draft. Ordered writes prevent older saves from restoring cleared content.
- Submission feedback reflects both dog and video review status. Pending tiles open a private status page with a preview, separate approval states, review updates, community guidelines, and the existing support page. Approved public videos retain the normal gallery playback journey.
- Moderation decisions generate private Activity updates. Approving a video while its profile is pending explains the remaining review. Internal moderator notes and reviewer identity are not included. Reviews have their own Activity filter.

## Connected backend

Migration `202610190001_review_notifications.sql` was applied to the existing TikDog project `scgoiuhfnhpuhftgmegx` in one transaction. Its source was recorded in `supabase_migrations.schema_migrations`. The dashboard confirmed `review_updates_installed = true`, `review_triggers = 2`, and `migration_recorded = true`.

The migration adds notifications for future review decisions; it does not backfill old decisions or change an existing submission's approval. Existing owner-only notification policies remain in force.

![Verified migration and review triggers](../.build-artifacts/journey-backend-review-proof.jpg)

## Verification

- All **31 Swift package tests** passed, including provider availability and combined review visibility.
- The complete iOS 26.5 run passed **45 native tests** and **20 UI tests**, with the separate Release-only configuration check skipped. It exercised the first-time poster, draft recovery across relaunch, private review status, existing upload flow, profile creation, social actions, cancellation, policies, and large-text screens.
- Local PostgreSQL checks passed for migrations, publication quarantine, ownership, private media, notifications, and moderation. New checks verify that guests and other members cannot read an owner's review updates and that internal moderation notes stay private.
- Signed iPhone Debug **build 6** succeeded using the existing development configuration.
- Final-source iOS 27 follow-up passed **46 native tests** and both provider/first-post UI checks. This includes shared draft-store ordering, reopened-draft edits, and preventing account-deletion cleanup from being undone by a late view save. Evidence: `journey-final-ios27.log` and `Journey-Final-iOS27.xcresult`.

Evidence is under `.build-artifacts/`: `journey-navigation-tests.log`, `journey-status-core-tests.log`, `journey-draft-tests.log`, `journey-native-all-tests.log`, `journey-database-tests.log`, `journey-complete-ios26.log`, `Journey-Complete-iOS26.xcresult`, `journey-signed-device-build.log`, and `journey-backend-review-proof.jpg`.

The first-post UI test uses an isolated demo account with no dogs and bundled movie bytes. It does not certify real Facebook authorization, camera recording, or a new live upload/moderation cycle. The existing phone build's unsaved in-memory draft cannot be migrated automatically by installing the new binary.

Screenshots: [saved draft](screenshots/16-Saved-draft.png), [submission status](screenshots/15-Submission-status.png). Device artifact: `.build-artifacts/iPhone14/Build/Products/Debug-iphoneos/TikDog.app`, bundle `com.jiaxing.tikdog.dev`, build 6. After the user authorized installation, build 6 was installed on Jia Xing’s iPhone 14, its installed bundle version was verified, and the app launched successfully. Evidence: `journey-build6-install.log`, `journey-build6-installed-app.log`, and `journey-build6-launch.log` under `.build-artifacts/`.

Reproduce the focused checks:

```sh
swift test --package-path TikDogCore
scripts/test_database.sh
xcodebuild -project TikDog.xcodeproj -scheme TikDog \
  -destination 'platform=iOS Simulator,id=917540F8-7443-40C6-96E1-DC1B348042B5' \
  -derivedDataPath .build-artifacts/Journey CODE_SIGNING_ALLOWED=NO \
  -only-testing:TikDogTests \
  -only-testing:TikDogUITests/TikDogUITests/testFirstPostCreatesDogAndRestoresDraftAfterRelaunch \
  -only-testing:TikDogUITests/TikDogUITests/testConnectedAppOffersOnlySocialSignIn test
```

Use an installed simulator ID if reproducing on another computer. The first-post fixture runs only in Debug with `--demo --reset-demo --demo-new-member`; relaunch without `--reset-demo` to retain its local account and draft.

## Deferred by request

- Paid Apple Developer configuration and live Apple authorization.
- Public website/domain and stable public video-sharing links. Existing sharing behavior is unchanged.

Operator/contact details and public policy configuration remain the existing release requirements. The native support navigation uses that existing policy content; no support address or moderation response time was invented.
