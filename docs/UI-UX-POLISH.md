# UI and UX simplification — 19 October 2026

The core loop is watching dogs, finding one to follow, and sharing a video. Each screen should make its next action clear.

- Discover has one dog grid instead of two lists of the same dogs. Search is prominent, tags occupy one horizontal row, and daily voting is a compact secondary entry. The grid still introduces dogs with smaller followings first.
- Feed keeps video, name, caption, and social actions. Removed the duplicate search shortcut, wordmark, breed badge, featured checkmarks, and fabricated “original sound” attribution. Sound state has an explicit label.
- Profile uses a smaller header so videos appear sooner. Removed decorative paw badges and a share action that sent generic text without a profile link. Videos and Saved have direct labels.
- Upload has one primary action, Choose a video. Recording is secondary. Labels describe selecting, trimming, captioning, posting, and review status.
- Activity hides filters when there is nothing to filter. Comments, authentication, and Settings use direct titles. Reporting, blocking, privacy, account controls, and moderation notices remain available.
- Secondary text has stronger contrast. Newly scaled headings, a single-column Discover grid at accessibility sizes, a scrollable upload picker, and visible disabled-button treatment support larger text.
- Deleted the unused section-heading component and avatar-ring option.

## Review and verification

Checklist: inspect source and existing screenshots; simplify; build; exercise real simulator paths; inspect fresh screenshots; review complete diff.

Two independent read-only reviews identified the same empty-profile copy error: upload guidance was shown to visitors. Fixed with owner-specific copy. No other substantiated blocker was reported. Rendered checks caught additional wrapping problems at the largest accessibility size. The voting entry stacks its labels, profile statistics use a vertical layout, and the upload intro omits decorative content at accessibility sizes. Compact playback controls scale up to the first accessibility size so both feed tabs remain legible.

This UI pass changes no backend contracts or data; concurrent Supabase authentication edits were left untouched. PR creation and deployment are outside this local UI task. No HTML prototype was used: this existing native interface is being iterated and checked directly in the simulator.

Completed checks:

- iPhone 17e, iOS 26.5: all 38 native tests passed. The complete UI run passed 18 scenarios and skipped the Release-only configuration check. One navigation test became ambiguous because both the Settings control and policy back button have the same label; it was scoped to the policy navigation bar and passed on rerun.
- iPhone 18 Pro, iOS 27: search/voting/profile editing, demo export/upload/review, tag gallery playback/return, and normal screenshots passed. Accessibility XXXL checks passed for comments, activity filters, dog search/profile opening, and reaching upload actions.
- After inspecting screenshots, reran the affected normal and accessibility paths after layout corrections. The final upload screenshot shows both action labels in full. Result bundles: `.build-artifacts/UI-Polish-Final-iOS27.xcresult`, `.build-artifacts/UI-Polish-Policy-Retry.xcresult`, `.build-artifacts/UI-Polish-Button-Final.xcresult`, and `.build-artifacts/UI-Polish-Large-Verified.xcresult`.
- Inspected fresh screenshots of feed, Discover, profiles, upload, activity, voting, and their tested accessibility variants. Updated `docs/screenshots/` with raw simulator captures. `git diff --check` passed.

Previews: [Discover](screenshots/02-Discover.png), [Profile](screenshots/03-Profile.png), [Upload](screenshots/04-Upload.png), [large-text Discover](screenshots/10-Large-text-discover.png), [large-text Profile](screenshots/11-Large-text-profile.png), [large-text Upload](screenshots/12-Large-text-upload.png).

Physical camera recording and completing live Apple/Facebook authentication were not exercised in this UI pass.
