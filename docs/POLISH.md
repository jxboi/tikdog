# Tikdog polish run — October 18, 2026

The user requested sustained local improvements through the current five-hour Codex usage window. Work is local; real social-provider and App Store launch requirements remain as recorded in `release/STATUS.md`.

The authorized October 19 morning continuation is recorded in [morning polish](MORNING-POLISH.md).

## Visible improvements

- The empty community offers a direct path to sharing or creating a dog profile. Search trims whitespace and dismisses its keyboard on submission.
- Profile and upload drafts offer explicit keep/discard choices. Creating a dog opens the new profile, and pending contributions remain private to their owner.
- Saved videos, votes, notification read state, comments and edited identities survive overlapping refreshes. Feed pagination continues after invalidated reads.
- Renewed media links preserve paused playback position. Imported movie cleanup respects file ownership, and delayed uploads cannot restore a deleted account's content.
- Activity filters have larger targets and selected states, and VoiceOver receives the unread notification count.

## Checklist

- [x] Inspect the current app, recorded verification, and available simulator.
- [x] Reproduce and fix the feed refresh crash and shared-catalog deletion.
- [x] Add native app-state tests to the generated Xcode project.
- [x] Verify search normalization, keyboard dismissal, and comment recovery.
- [x] Verify newly saved photos and recovered uploads include usable private-media URLs.
- [x] Finish the complete iOS 26.5 UI pass and inspect its screenshots.
- [x] Resolve the review findings around ordinary refreshes and overlapping profile requests.
- [x] Verify upload ownership, invalid replacement, and complete export/publish flow.
- [x] Finish the second runtime pass on iOS 27.0.
- [x] Check playback continuity when private-media access is renewed, including consecutive renewals.
- [x] Give the empty community a path to sharing and profile creation.
- [x] Protect profile drafts with visible keep/discard choices.
- [x] Disable unchanged profile saves to avoid unnecessary moderation.
- [x] Preserve completed writes when an older full refresh arrives.
- [x] Keep read-only catalog hydration separate from local writes.
- [x] Protect completed votes and notification read state from delayed refreshes.
- [x] Verify multi-dog creation, review privacy and persistence.
- [x] Improve activity filter targets and accessible unread state.
- [x] Preserve comments posted during a delayed reload.
- [x] Select newly created dogs immediately and protect upload drafts.
- [x] Prevent late upload responses from restoring a deleted account's content.
- [x] Preserve newly edited identities when older feed/profile requests finish.
- [x] Retry invalidated page/profile reads so loading still makes progress.
- [x] Refresh the active Following feed after changing follows.
- [x] Refresh and inspect the four project preview screenshots.
- [ ] Continue focused usability checks while usage remains available.

## Evidence

The append-only decision trail is `.audit/tikdog-polish.tsv`. Reproducible tests live in `TikDogTests`, `TikDogUITests`, and `TikDogCore/Tests`; generated result bundles and logs are under `.build-artifacts/`.

- `polish-state-red.log` reproduced a Swift exclusive-access crash during feed refresh and an incorrectly visible moderated video. `polish-state-green.log` passed both tests after the fix.
- `polish-bookmark-red2.log` reproduced a late save response restoring state after account deletion. `polish-session-search.log` passed that regression and the search/social UI checks. Review identified an additional same-member refresh ordering that is being corrected separately.
- `polish-comments-red.log` reproduced lost newer draft text, retained error text after retry, and exposed cancellation errors. `polish-comments-green.log` passed six native tests and the comment report/block UI flows.
- `polish-media-red.log` reproduced missing signed photo/playback URLs. `polish-core-media-green.log` passed all 28 core tests after hydration was added to saved profiles and recovered uploads.
- `polish-full-ios26.log` passed six native tests and eleven UI tests, with one Release-only test skipped. The subsequent fixes are covered by follow-up runs.
- `polish-review-red.log` reproduced a successful save being ignored after a same-member refresh, an older profile replacing a completed refresh, and an older request clearing the new request's loading indicator. `polish-review-green.log` passed all nine native tests and the discovered-profile/gallery UI test. A second read-only review found no further issues in those two fixes.
- `polish-upload-red.log` showed cleanup deleting a borrowed movie. `polish-upload-green.log` passed twelve native tests, including actual bundled-movie validation and file ownership, plus the complete export/publish/profile UI flow.
- `polish-full-ios27.log` passed twelve native and eleven UI tests, with one Release-only skip. Playback and onboarding changes made afterward have dedicated checks.
- `polish-playback-red2.log` reproduced lost playback position after a valid initial seek. `polish-playback-rapid-red.log` caught a second URL renewal losing a pending seek. `polish-refinements-green.log` verifies both against actual media, along with the other native state checks.
- `polish-onboarding.log` passed thirteen native checks, the connected guest empty-community flow, and the full demo upload. The empty feed screenshot was inspected directly.
- `polish-profile-draft-red.log` reproduced accidental draft loss. The first confirmation implementation failed because the platform popover hid its cancel choice; `polish-draft-diagnostic/` contains the actual screenshot and accessibility hierarchy. An explicit alert offers both choices, and the keep/discard UI flow passes in `polish-refinements-green.log`.
- `polish-device-release.log` records a successful unsigned iPhone Release compilation before the subsequent profile-draft refinement. A final build will cover that refinement too.
- The verification script now selects an installed iPhone. `polish-simulator-destination.txt` records the actual selected iOS 27.0 device, which also ran the second full suite.
- `polish-integrated-verification.log` passed the complete local release entry point: 29 core, 11 Edge, six release-gate, fourteen native and thirteen UI tests, with one Release-only skip, plus PostgreSQL authorization checks. Publication remains blocked by the existing external launch gates.
- `polish-refresh-reverse-red.log` reproduced an older bootstrap erasing a completed bookmark. The fix retries once after a local write and retains newer state if writes continue through the second request. Deterministic tests cover both save/refresh orderings and this bounded retry.
- `polish-hydration-red.log` caught read-only catalog updates incorrectly preventing a refresh from committing. Explicit local-write methods now distinguish writes from hydration; `polish-hydration-green.log` passed all seventeen native tests plus block/unblock, social feed and search UI checks. `polish-core-merge.log` passed all 29 core tests after the shared catalog merge moved into `AppSnapshot`.
- `polish-noop-red.log` reproduced an enabled save for an unchanged profile. `polish-refresh-noop-green.log` verifies unchanged, changed and reverted form states in the real editor.
- `polish-partial-refresh-red.log` reproduced an older voting refresh undoing a completed vote and an older activity refresh restoring three read notifications. `polish-partial-refresh-green.log` passed all nineteen native checks and the vote UI after both reads gained the local-write revision guard. Independent review found no actionable issues.
- `polish-pack-flow.log` passed new-dog creation, public-search exclusion while awaiting review, persistence after relaunch, unchanged-profile editing, and actual export/publish. The pending profile screenshot in `polish-pack-shots/` was inspected.
- `polish-activity.log` verifies follower/interaction filtering, opening the follower's profile and clearing unread state. Activity filters now expose selection and have 44-point targets; the navigation item exposes its unread count to VoiceOver. The resulting screenshot in `polish-activity-shots/` was inspected.
- `polish-comment-refresh-red.log` reproduced a successful post disappearing when an older load completed. The retained regression now verifies existing comments and the new post survive, the next reload deduplicates, and a later authoritative removal is respected. An unrelated count probe assumed immediate approval; it was removed because pending comments correctly do not increase public counts.
- `polish-new-dog-selection-red.log` reproduced creation returning to the previous dog's profile. The saved-dog callback now selects the new profile after inserting it into the catalog. `polish-upload-draft-red.log` reproduced the hidden Keep editing choice; an alert exposes both draft choices. `polish-publish-session-red.log` reproduced a delayed export/publish result restoring deleted-account content; session guards reject it. `polish-upload-followup-green.log` passes 21 native and three UI checks for these changes. A final extra session check before publishing is included in the next complete run.
- `polish-device-release-final.log` records a successful unsigned iPhone Release compilation through the upload and profile-selection changes; the later feed target and modal-coverage refinements need the final incremental build.
- `polish-complete-current.log` passed the complete iOS 26.5 suite: 21 native tests and 17 UI tests, with one Release-only skip. This includes the final pre-publish session check, wider feed search target and playback suspension for terms/error modals. `polish-current-screenshots/` contains the four inspected captures copied to `docs/screenshots/`.
- `polish-profile-write-red.log` and `polish-feed-write-red.log` reproduced older reads restoring an edited dog's previous name and approved status. `polish-following-red.log` reproduced unfollowing one dog clearing other followed dogs from the active feed. The revision guards and Following reload pass in `polish-read-ownership-green.log` (24 native and three relevant UI tests).
- Independent review caught a loading regression in the first guard implementation: silently discarding a stale page could stop pagination, and an initial profile could remain empty. `polish-read-liveness-red.log` reproduces both. Feed/profile requests now retain ownership and fetch again when a concurrent write invalidates the result; cancellation, a newer request, epoch changes and failures end the request. `polish-read-liveness-green.log` passes 26 native tests and both gallery/feed UI flows. The final integrated run adds two consecutive page invalidations and an unfollow while an older Following page is pending.

No measured performance improvement is claimed. Real Facebook/Apple authorization, physical-device camera/signing, public operator details and App Store submission remain outside these local checks.
