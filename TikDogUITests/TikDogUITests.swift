import XCTest

@MainActor final class TikDogUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--reset-demo"]
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        app.launch(); XCTAssertTrue(app.buttons["tab-discover"].waitForExistence(timeout: 15)); return app
    }
    func testFeedSocialAndFollowing() throws {
        let app = launch()
        XCTAssertTrue(app.scrollViews["videoFeed"].waitForExistence(timeout: 10))
        let like = app.buttons["Like video"].firstMatch
        XCTAssertTrue(like.waitForExistence(timeout: 10)); like.tap()
        XCTAssertTrue(app.buttons["Unlike video"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["Save video"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Unsave video"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["Open comments"].firstMatch.tap()
        let draft = app.textFields["commentDraft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5)); draft.tap(); draft.typeText("Certified good dog!")
        app.buttons["Post comment"].tap()
        XCTAssertTrue(app.staticTexts["Certified good dog!"].waitForExistence(timeout: 5))
        app.buttons["Close comments"].tap(); app.buttons["tab-discover"].tap()
        XCTAssertTrue(app.staticTexts["Find your pack."].waitForExistence(timeout: 5))
    }
    func testSearchVoteAndProfile() throws {
        let app = launch(); app.buttons["tab-discover"].tap()
        let search = app.textFields["dogSearch"]; XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Shiba")
        XCTAssertTrue(app.staticTexts["Mochi"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Clear search"].tap(); app.swipeDown()
        app.buttons["dailyVoteHero"].tap()
        let vote = app.buttons["vote-cabby"]; XCTAssertTrue(vote.waitForExistence(timeout: 5)); vote.tap()
        XCTAssertTrue(app.buttons["Voted ✓"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap(); app.buttons["tab-profile"].tap()
        XCTAssertTrue(app.buttons["editDog"].waitForExistence(timeout: 5)); app.buttons["editDog"].tap()
        let name = app.textFields["dogNameInput"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); XCTAssertEqual(name.value as? String, "Cabby")
    }
    func testActivityFiltersOpenTheRightProfileAndClearUnreadState() throws {
        let app = launch()
        let activity = app.buttons["tab-activity"]
        XCTAssertEqual(activity.value as? String, "3 unread notifications")
        activity.tap()
        let followers = app.buttons["Followers"]
        XCTAssertTrue(followers.waitForExistence(timeout: 5)); followers.tap()
        XCTAssertTrue(followers.isSelected)
        let followMessage = "Mochi's person started following Cabby."
        XCTAssertTrue(app.staticTexts[followMessage].exists)
        XCTAssertFalse(app.staticTexts["Milo's person: That little face! 🥹"].exists)
        app.staticTexts[followMessage].tap()
        XCTAssertTrue(app.buttons["Close profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mochi"].exists)
        app.buttons["Close profile"].tap()
        app.buttons["Interactions"].tap()
        XCTAssertTrue(app.buttons["Interactions"].isSelected)
        XCTAssertFalse(app.staticTexts[followMessage].exists)
        XCTAssertTrue(app.staticTexts["Milo's person: That little face! 🥹"].exists)
        XCTAssertEqual(activity.value as? String, "No unread notifications")
        save(app, name: "Activity-interactions")
    }
    func testLargeTextCommentsAndActivityRemainUsable() throws {
        let message = "The internet was made for this little face 🥹"
        let normal = launch(); normal.buttons["Open comments"].firstMatch.tap()
        XCTAssertTrue(normal.staticTexts[message].waitForExistence(timeout: 5))
        let normalBodyHeight = normal.staticTexts[message].frame.height
        let normalCountHeight = normal.staticTexts["1"].firstMatch.frame.height
        normal.terminate()

        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        app.buttons["Open comments"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.staticTexts["1"].firstMatch.frame.height, normalCountHeight * 1.4)
        XCTAssertGreaterThan(app.staticTexts[message].frame.height, normalBodyHeight * 1.4)
        save(app, name: "Large-text-comments")
        let draft = app.textFields["commentDraft"]
        draft.tap(); draft.typeText("A very good dog")
        app.buttons["Post comment"].tap()
        XCTAssertTrue(app.staticTexts["A very good dog"].waitForExistence(timeout: 5))
        app.buttons["Close comments"].tap(); app.buttons["tab-activity"].tap()
        let filters = app.scrollViews["activityFilters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 5)); filters.swipeLeft()
        app.buttons["Interactions"].tap()
        XCTAssertTrue(app.buttons["Interactions"].isSelected)
        XCTAssertTrue(app.staticTexts["Milo's person: That little face! 🥹"].exists)
        save(app, name: "Large-text-activity")
    }
    func testSearchTrimsWhitespaceAndDismissesKeyboardOnSubmit() throws {
        let app = launch(); app.buttons["tab-discover"].tap()
        let search = app.textFields["dogSearch"]
        search.tap(); search.typeText("   ")
        XCTAssertTrue(app.buttons["dailyVoteHero"].exists)
        app.buttons["Clear search"].tap()
        search.tap(); search.typeText("  Shiba  \n")
        XCTAssertTrue(app.staticTexts["Mochi"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dailyVoteHero"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        save(app, name: "Search-results")
        app.buttons["Clear search"].tap()
        XCTAssertTrue(app.buttons["dailyVoteHero"].waitForExistence(timeout: 5))
    }
    func testProfileEditsCanBeKeptOrExplicitlyDiscarded() throws {
        let app = launch(); app.buttons["tab-profile"].tap(); app.buttons["editDog"].tap()
        let name = app.textFields["dogNameInput"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText(" Junior")
        XCTAssertEqual(name.value as? String, "Cabby Junior")
        app.buttons["Cancel"].tap()
        let keep = app.buttons["Keep editing"]
        let offered = keep.waitForExistence(timeout: 5)
        save(app, name: "Profile-draft-discard-dialog")
        XCTAssertTrue(offered); keep.tap()
        XCTAssertEqual(name.value as? String, "Cabby Junior")
        app.buttons["Cancel"].tap(); app.buttons["Discard changes"].tap()
        XCTAssertTrue(app.buttons["editDog"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Cabby"].exists)
        XCTAssertFalse(app.staticTexts["Cabby Junior"].exists)
    }
    func testUnchangedProfileDoesNotRequestAnotherReview() throws {
        let app = launch(); app.buttons["tab-profile"].tap(); app.buttons["editDog"].tap()
        let name = app.textFields["dogNameInput"], save = app.buttons["Save profile"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        name.tap(); name.typeText("   ")
        XCTAssertFalse(save.isEnabled)
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        name.typeText(" Junior")
        XCTAssertTrue(save.isEnabled)
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))
        XCTAssertEqual(name.value as? String, "Cabby")
        XCTAssertFalse(save.isEnabled)
        let breed = app.textFields["dogBreedInput"]
        breed.tap(); breed.typeText("   ")
        XCTAssertFalse(save.isEnabled)
    }
    func testNewDogCanBeSelectedAndStaysPrivateUntilReview() throws {
        let app = launch(); app.buttons["tab-profile"].tap()
        app.buttons["packMenu"].tap(); app.buttons["Add a dog"].tap()
        let name = app.textFields["dogNameInput"], breed = app.textFields["dogBreedInput"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Pepper")
        breed.tap(); breed.typeText("Rescue mix")
        app.swipeUp()
        let create = app.buttons["Welcome to the pack"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); XCTAssertTrue(create.isEnabled); create.tap()
        XCTAssertTrue(app.buttons["packMenu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pepper"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Profile awaiting review"].exists)
        save(app, name: "New-private-profile")
        app.buttons["tab-home"].tap(); app.buttons["tab-profile"].tap()
        XCTAssertTrue(app.staticTexts["Pepper"].waitForExistence(timeout: 5))
        app.buttons["tab-upload"].tap(); app.buttons["useDemoClip"].tap()
        let featured = app.buttons["featuredDogPicker"]
        XCTAssertTrue(featured.waitForExistence(timeout: 5))
        XCTAssertTrue(featured.label.contains("Pepper") || featured.value as? String == "Pepper")
        let caption = app.descendants(matching: .any).matching(identifier: "uploadCaption").firstMatch
        caption.tap(); caption.typeText("Pepper's first adventure")
        app.swipeUp(); app.buttons["publishVideo"].tap()
        XCTAssertTrue(app.buttons["uploadSuccess"].waitForExistence(timeout: 60)); app.buttons["uploadSuccess"].tap()
        XCTAssertTrue(app.staticTexts["Pepper"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Play Pepper's first adventure"].waitForExistence(timeout: 5))
        app.buttons["tab-discover"].tap()
        let search = app.textFields["dogSearch"]
        search.tap(); search.typeText("Pepper\n")
        XCTAssertTrue(app.staticTexts["No tails found"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["tab-profile"].waitForExistence(timeout: 10)); app.buttons["tab-profile"].tap()
        app.buttons["packMenu"].tap()
        XCTAssertTrue(app.buttons["Pepper"].waitForExistence(timeout: 5))
    }
    func testDemoUploadWaitsForReview() throws {
        let app = launch(); app.buttons["tab-upload"].tap()
        app.buttons["useDemoClip"].tap()
        let caption = app.descendants(matching: .any).matching(identifier: "uploadCaption").firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 10)); caption.tap(); caption.typeText("My first TikDog adventure")
        app.swipeUp(); let publish = app.buttons["publishVideo"]; XCTAssertTrue(publish.waitForExistence(timeout: 5)); publish.tap()
        XCTAssertTrue(app.buttons["uploadSuccess"].waitForExistence(timeout: 60)); app.buttons["uploadSuccess"].tap()
        XCTAssertTrue(app.buttons["Play My first TikDog adventure"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["In review"].firstMatch.waitForExistence(timeout: 5))
        save(app, name: "05-Pending-review")
        app.buttons["tab-home"].tap()
        XCTAssertTrue(app.scrollViews["videoFeed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["My first TikDog adventure"].exists)
    }
    func testUploadDraftCanBeKeptOrExplicitlyDiscarded() throws {
        let app = launch(); app.buttons["tab-upload"].tap(); app.buttons["useDemoClip"].tap()
        let caption = app.descendants(matching: .any).matching(identifier: "uploadCaption").firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 10)); caption.tap(); caption.typeText("Keep this adventure")
        app.buttons["Close upload"].tap()
        XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
        app.buttons["Keep editing"].tap()
        XCTAssertEqual(caption.value as? String, "Keep this adventure")
        app.buttons["Close upload"].tap(); app.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["tab-upload"].waitForExistence(timeout: 5))
        app.buttons["tab-upload"].tap()
        XCTAssertTrue(app.buttons["useDemoClip"].waitForExistence(timeout: 5))
        XCTAssertFalse(caption.exists)
    }
    func testSwipePauseAndFollowingFeed() throws {
        let app = launch()
        let feed = app.scrollViews["videoFeed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 10))
        let original = feed.value as? String ?? ""
        feed.swipeUp()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", original), object: feed)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        app.buttons["feed-following"].tap()
        let following = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Mochi"), object: feed)
        XCTAssertEqual(XCTWaiter.wait(for: [following], timeout: 5), .completed)
        let surface = try XCTUnwrap(app.descendants(matching: .any).matching(identifier: "videoSurface").allElementsBoundByIndex.first(where: { $0.isHittable && ($0.value as? String) == "Playing" }))
        surface.tap()
        save(app, name: "Playback-after-tap")
        XCTAssertTrue(app.images["pausedIndicator"].waitForExistence(timeout: 5))
        surface.tap()
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.images["pausedIndicator"])
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 5), .completed)
        surface.tap()
        XCTAssertTrue(app.images["pausedIndicator"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.images["pausedIndicator"].waitForExistence(timeout: 10))
    }
    func testDiscoveredDogGalleryPlaysAboveProfile() throws {
        let app = launch(); app.buttons["tab-discover"].tap()
        let search = app.textFields["dogSearch"]; search.tap(); search.typeText("Mochi")
        let dog = app.buttons.containing(.staticText, identifier: "Mochi").firstMatch
        XCTAssertTrue(dog.waitForExistence(timeout: 5)); dog.tap()
        let clip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play ")).firstMatch
        XCTAssertTrue(clip.waitForExistence(timeout: 5)); clip.tap()
        let close = app.buttons["Close video"]
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        XCTAssertTrue(app.buttons["Close profile"].waitForExistence(timeout: 5))
        app.buttons["Close profile"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
    }
    func testReportCommentHidesIt() throws {
        let app = launch()
        app.buttons["Open comments"].firstMatch.tap()
        let comment = app.staticTexts["The internet was made for this little face 🥹"]
        XCTAssertTrue(comment.waitForExistence(timeout: 5))
        app.buttons["Comment options"].firstMatch.tap()
        app.buttons["Report comment"].tap()
        XCTAssertTrue(app.staticTexts["Start the conversation"].waitForExistence(timeout: 5))
        XCTAssertFalse(comment.exists)
    }
    func testBlockAndUnblockCommentAuthor() throws {
        let app = launch()
        app.buttons["Open comments"].firstMatch.tap()
        app.buttons["Comment options"].firstMatch.tap()
        app.buttons["Block this account"].tap()
        XCTAssertTrue(app.staticTexts["Start the conversation"].waitForExistence(timeout: 5))
        app.buttons["Close comments"].tap()
        app.buttons["tab-profile"].tap(); app.buttons["Settings"].tap()
        app.buttons["Blocked accounts"].tap()
        XCTAssertTrue(app.buttons["Unblock"].waitForExistence(timeout: 5)); app.buttons["Unblock"].tap()
        XCTAssertTrue(app.staticTexts["You haven't blocked any accounts."].waitForExistence(timeout: 5))
    }
    func testPoliciesAndSupportAreAccessible() throws {
        let app = launch(); app.buttons["tab-profile"].tap(); app.buttons["Settings"].tap()
        app.buttons["Privacy policy"].tap()
        XCTAssertTrue(app.staticTexts["Who operates TikDog"].waitForExistence(timeout: 5))
        save(app, name: "06-Privacy")
        app.buttons["The little details"].tap()
        app.buttons["Contact & support"].tap()
        XCTAssertTrue(app.staticTexts["Contact us"].waitForExistence(timeout: 5))
    }
    func testDeletingDemoAccountReturnsToGuestProfile() throws {
        let app = launch(); app.buttons["tab-profile"].tap(); app.buttons["Settings"].tap()
        app.swipeUp()
        let delete = app.buttons["Delete account"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        let confirm = app.sheets.buttons["Delete account"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.buttons["Join the pack"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["editDog"].exists)
        app.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons["Delete account"].exists)
        XCTAssertTrue(app.buttons["Sign in or create an account"].exists)
    }
    func testReleaseConfigurationNeverBecomesDemo() throws {
        #if DEBUG
        throw XCTSkip("Runs separately with the Release configuration and no production credentials")
        #else
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--reset-demo"]; app.launch()
        XCTAssertTrue(app.staticTexts["TikDog is unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["tab-discover"].exists)
        save(app, name: "07-Release-unavailable")
        #endif
    }
    func testConnectedAppOffersOnlySocialSignIn() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["tab-profile"].waitForExistence(timeout: 15)); app.buttons["tab-profile"].tap()
        let join = app.buttons["Join the pack"]
        guard join.waitForExistence(timeout: 5) else { throw XCTSkip("Requires a connected app with a signed-out session") }
        join.tap()
        let facebook = app.buttons["facebookSignIn"], apple = app.buttons["appleSignIn"]
        XCTAssertTrue(facebook.waitForExistence(timeout: 5)); XCTAssertTrue(apple.exists)
        XCTAssertFalse(facebook.isEnabled); XCTAssertFalse(apple.isEnabled)
        XCTAssertFalse(app.textFields["Email address"].exists); XCTAssertEqual(app.secureTextFields.count, 0)
        XCTAssertFalse(app.buttons["Forgot your password?"].exists)
        app.switches["signupConsent"].tap()
        XCTAssertTrue(facebook.isEnabled); XCTAssertTrue(apple.isEnabled)
        save(app, name: "08-Social-sign-in")
        app.buttons["Continue as guest"].tap()
        XCTAssertTrue(join.waitForExistence(timeout: 5))
    }
    func testConnectedEmptyCommunityOffersAPathToContribute() throws {
        let app = XCUIApplication(); app.launch()
        let share = app.buttons["emptyFeedAction"]
        guard share.waitForExistence(timeout: 15) else { throw XCTSkip("Requires a connected app with an empty public feed") }
        XCTAssertEqual(share.label, "Share an adventure")
        share.tap()
        XCTAssertTrue(app.buttons["facebookSignIn"].waitForExistence(timeout: 5))
        app.buttons["Continue as guest"].tap()
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        save(app, name: "Empty-feed")
        app.buttons["tab-discover"].tap()
        guard app.staticTexts["The pack is growing"].waitForExistence(timeout: 5) else { throw XCTSkip("Requires an empty public dog directory") }
        XCTAssertFalse(app.staticTexts["No tails found"].exists)
        app.buttons["Meet my dog"].tap()
        XCTAssertTrue(app.buttons["Join the pack"].waitForExistence(timeout: 5))
    }
    func testCaptureScreenshots() throws {
        let app = launch()
        sleep(3)
        save(app, name: "01-Feed")
        app.buttons["tab-discover"].tap(); sleep(1); save(app, name: "02-Discover")
        app.buttons["tab-profile"].tap(); sleep(1); save(app, name: "03-Profile")
        app.buttons["tab-upload"].tap(); sleep(1); save(app, name: "04-Upload")
    }
    private func save(_ app: XCUIApplication, name: String) { let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment) }
}
