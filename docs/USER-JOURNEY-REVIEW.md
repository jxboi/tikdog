# User journey review — 19 October 2026

Implementation follow-up: [delivered journey changes and verification](JOURNEY-IMPLEMENTATION.md). Live Apple setup and public sharing links were deferred at the user's request; the remaining recommendations have been implemented.

The main weakness is the handoff between screens. Browsing is straightforward, but a new member must discover how signing in, creating a dog profile, submitting a video, and moderation connect. The recent Facebook and posting reports expose that gap.

This review uses the current Swift source, the user's two device screenshots, saved simulator screenshots, existing test coverage, and a fresh read of the connected project's public Auth settings. It is not a newly completed live first-post test. No app or backend settings were changed during this review.

## Findings, ordered by impact

### 1. High — Apple is offered as a working sign-in option while its provider is disabled

Both social buttons become enabled after consent. A fresh read of `/auth/v1/settings` confirmed Facebook enabled and Apple disabled. Choosing Apple cannot complete the configured backend flow, even if native authorization succeeds.

Complete Apple configuration and physical-device verification before offering this path as available. During development, clearly indicate its availability. Keep this separate from the already corrected Facebook callback validator.

Evidence: [AuthView.swift](../TikDog/Features/AuthView.swift#L31), [provider setup](release/SOCIAL_LOGIN.md).

### 2. High — Signing in loses the action that prompted it

A guest taps Upload; `presentUpload()` opens authentication and returns. Successful authentication dismisses the sheet, reloads data, and shows a welcome toast. Nothing reopens Upload. Profile creation and guest feed interactions have the same missing continuation: the user must repeat the action.

Remember the requested destination and resume it after successful authentication and terms acceptance. Resume navigation immediately; for likes, follows, and other mutations, preserve the target context and make the next action clear. Canceling sign-in should leave the user at the original screen.

Evidence: [AppModel.swift](../TikDog/App/AppModel.swift#L168), [AuthView.swift](../TikDog/Features/AuthView.swift#L84), [MyProfileView](../TikDog/Features/ProfileView.swift#L41).

### 3. High — First-time posting reveals its prerequisite after the user has selected a clip

The upload entry offers video selection immediately. Only the editor reveals that a dog profile is required. The user's screenshot shows the consequence: a disabled Post button and an easily missed text action above it.

For the posting journey, offer dog setup before the media picker when no dog exists, then continue directly to video selection. Existing owners should skip setup. People who only watch or follow dogs should never need a dog profile.

The prepared build 5 improves this editor state with an enabled **Add your dog to continue** button and draft-preservation guidance. This reduces the dead end, but it does not yet move setup earlier. Build 5 was left uninstalled to preserve the user's open upload draft.

Evidence: [upload entry](../TikDog/Features/UploadView.swift#L155), [editor prerequisite](../TikDog/Features/UploadView.swift#L194), [prepared button](../TikDog/Features/UploadView.swift#L220), user's posting screenshot.

### 4. Medium — Dog creation repeats the unexplained disabled-button pattern

Saving requires both a name and breed, but neither field is explicitly marked required. The save button says **Welcome to the pack**, which does not describe saving a dog profile. A person who supplies only a name may again interpret a disabled button as a fault.

Label required fields and use **Save dog and continue** inside the posting journey. Mark photo, birthday, and bio as optional. Explain missing requirements beside the relevant field. Consider whether breed needs to be required at all; changing that requirement would also need backend validation review.

Evidence: [save eligibility](../TikDog/Features/ProfileView.swift#L199), [fields and button](../TikDog/Features/ProfileView.swift#L219).

### 5. Medium — Draft recovery ends when the app process ends

The source clip, trim positions, caption, and selected dog live in the upload view model. Close/discard confirmation and retry protection help during the active session, but there is no saved-draft restoration after termination or an app update. The owned temporary source file is removed on cleanup.

Persist a recoverable local draft after media import and meaningful edits. Offer **Continue draft** and **Discard draft** on the next upload entry. Keep draft files private and separate from published media. Do not describe this as a backgrounding failure: the current code does not establish that ordinary backgrounding loses the draft.

Evidence: [UploadViewModel](../TikDog/Features/UploadView.swift#L18), [cleanup](../TikDog/Features/UploadView.swift#L111), [view state](../TikDog/Features/UploadView.swift#L122).

### 6. Medium — Submission feedback does not explain the full path to public visibility

The success screen correctly says the video awaits review and links to its profile. However, public visibility requires both the video and its dog profile to be approved. A newly created dog and its first video can therefore be waiting on two reviews. The owner sees separate status labels but no unified explanation, review decision history, or next step for removed content.

Show **Submitted — visible only to you** and explain whether the dog profile, video, or both are awaiting review. Keep a direct **View submission** action. Provide decision feedback and a support or appeal route for removed content. State a review timeframe only if operations can reliably meet it.

Evidence: [success screen](../TikDog/Features/UploadView.swift#L232), [owner profile status](../TikDog/Features/ProfileView.swift#L97), [video badges](../TikDog/Features/ProfileView.swift#L150), [public visibility](../supabase/migrations/202610180004_release_safety.sql#L130).

### 7. Medium — Shared video links expire

Share sends the current playback URL. Hosted private media URLs are signed for 900 seconds, so a recipient opening that link later can find an expired resource. This weakens the loop from sharing a dog video to bringing another person into TikDog.

Share a stable public video page or deep link that resolves current permissions and obtains a fresh playback URL. Pending or removed content must remain inaccessible to other people.

Evidence: [ShareLink](../TikDog/Features/FeedView.swift#L213), [signed media lifetime](../TikDogCore/Sources/TikDogCore/SupabaseRepository.swift#L237).

## Recommended journeys

**Viewer:** Browse as guest → discover a dog → follow or save → sign in if needed → return to that dog or video. Dog creation is optional.

**First-time poster:** Tap + → sign in if needed → add a dog if needed → choose or record video → trim and caption → submit → see private review status → receive the review outcome.

**Returning poster:** Tap + → continue a saved draft or choose video → confirm featured dog → submit → see review status.

**Recovery:** Cancel authentication → return to the original context. Cancel dog creation → retain the upload context. Upload failure → retain edits and offer retry. Relaunch → offer the saved draft.

## What already works well

- Guests can browse without an account.
- Existing owners can choose among their dogs.
- Upload has distinct preparing, uploading, and submitted states.
- Explicit discard confirmations protect active profile and upload edits.
- Pending submissions appear in the owner's profile and stay out of public feeds.
- Empty feeds, failed feeds, and empty search results have distinct messages.

The previous turn's two simulator checks passed for demo submission/review and upload keep/discard behavior. Existing UI coverage also exercises adding another dog and selecting it for upload. That does not cover a brand-new real account completing authentication, its first dog, its first upload, and both moderation approvals in one journey.

## Implementation and verification order

1. Resolve the unavailable Apple route and resume navigation after authentication.
2. Move first-dog setup into the posting entry and make form requirements explicit.
3. Add durable drafts and unified submission status.
4. Replace expiring share URLs with stable links.

Verify with a clean account that owns no dogs, an existing owner, and a viewer who does not own a dog. Include authentication cancellation, canceled dog setup, a failed upload/retry, termination/relaunch, and separate dog/video approval states. Preserve the current user's device draft while testing in an isolated account or simulator.
