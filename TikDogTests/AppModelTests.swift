import XCTest
import TikDogCore
@testable import TikDog

@MainActor final class AppModelTests: XCTestCase {
    func testGuestUploadResumesOnceAfterAuthentication() {
        let app = AppModel(repository: DemoRepository())
        app.presentUpload()
        XCTAssertTrue(app.showAuth)
        XCTAssertFalse(app.isUploadPresented)
        app.applyLocalChange { $0.userId = DemoContent.ownerId }
        app.accountState.termsVersion = CommunityTerms.version
        app.showAuth = false
        app.authenticationDidDismiss()
        XCTAssertTrue(app.isUploadPresented)
        XCTAssertNil(app.pendingMemberDestination)
        app.isUploadPresented = false
        app.authenticationDidDismiss()
        XCTAssertFalse(app.isUploadPresented)
    }

    func testCanceledAuthenticationDoesNotResumeAnOldUpload() {
        let app = AppModel(repository: DemoRepository())
        app.presentUpload(); app.showAuth = false; app.authenticationDidDismiss()
        app.applyLocalChange { $0.userId = DemoContent.ownerId }
        app.accountState.termsVersion = CommunityTerms.version
        app.authenticationDidDismiss()
        XCTAssertFalse(app.isUploadPresented)
        XCTAssertNil(app.pendingMemberDestination)
    }

    func testDogCreationResumesAfterTermsAndDoesNotForceViewersToCreateADog() {
        let app = AppModel(repository: DemoRepository())
        app.applyLocalChange { $0.userId = DemoContent.ownerId }
        app.presentDogCreation()
        XCTAssertTrue(app.showTerms)
        XCTAssertFalse(app.isDogCreationPresented)
        app.accountState.termsVersion = CommunityTerms.version; app.showTerms = false
        app.resumeMemberDestination()
        XCTAssertTrue(app.isDogCreationPresented)
        app.isDogCreationPresented = false
        XCTAssertTrue(app.requireMember())
        XCTAssertFalse(app.isDogCreationPresented)
    }

    func testSuccessfulDeletionClearsPrivateStateEvenWhenGuestRefreshFails() async throws {
        let delay = DeferredBootstrap()
        let repository = DeferredRepository(bootstrapDelay: delay)
        let app = AppModel(repository: repository)
        await app.load()
        let dog = try XCTUnwrap(app.selectedOwnDog)
        let video = try XCTUnwrap(app.homeVideos.first)
        let oldSession = app.sessionEpoch
        app.selectedOwnDogId = dog.id; app.selectedDog = dog; app.selectedVideo = video
        let bookmark = Task { await app.bookmark(video) }
        await repository.bookmarkGate.waitUntilStarted()
        let gate = await delay.enqueue()
        let deletion = Task { try await app.deleteAccount() }
        await gate.waitUntilStarted()
        XCTAssertNil(app.snapshot.userId)
        XCTAssertNil(app.selectedOwnDog)
        await gate.finish(throwing: URLError(.notConnectedToInternet))
        try await deletion.value
        await repository.bookmarkGate.finish()
        await bookmark.value

        XCTAssertNil(app.snapshot.userId)
        XCTAssertTrue(app.snapshot.dogs.isEmpty)
        XCTAssertTrue(app.snapshot.bookmarkedVideoIds.isEmpty)
        XCTAssertNil(app.selectedOwnDogId)
        XCTAssertNil(app.selectedDog)
        XCTAssertNil(app.selectedVideo)
        XCTAssertNotEqual(app.sessionEpoch, oldSession)
        XCTAssertNotNil(app.feedFailures[.forYou])
        XCTAssertNil(app.toast)
    }

    func testFailedDeletionRetainsTheAccountForRetry() async throws {
        let gate = RequestGate()
        let app = AppModel(repository: DeferredRepository(deleteGate: gate))
        await app.load()
        let owner = try XCTUnwrap(app.snapshot.userId)
        let session = app.sessionEpoch
        let deletion = Task { try await app.deleteAccount() }
        await gate.waitUntilStarted()
        await gate.finish(throwing: URLError(.notConnectedToInternet))
        do { try await deletion.value; XCTFail("Deletion should fail") }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }

        XCTAssertEqual(app.snapshot.userId, owner)
        XCTAssertNotNil(app.selectedOwnDog)
        XCTAssertEqual(app.sessionEpoch, session)
    }

    func testSelectedOwnDogSurvivesRefreshAndClearsAfterAccountDeletion() async throws {
        let repository = DemoRepository()
        let app = AppModel(repository: repository)
        await app.load()
        let owner = try XCTUnwrap(app.snapshot.userId)
        let pepper = try await repository.saveDog(Dog(ownerId: owner, name: "Pepper", breed: "Rescue mix"))
        app.mergeLocal(dogs: [pepper]); app.selectedOwnDogId = pepper.id

        await app.load()
        XCTAssertEqual(app.selectedOwnDog?.id, pepper.id)
        XCTAssertEqual(app.selectedOwnDog?.name, "Pepper")
        try await app.deleteAccount()

        XCTAssertNil(app.selectedOwnDogId)
        XCTAssertNil(app.selectedOwnDog)
    }

    func testRefreshingFollowingPreservesVideosUsedByForYouAndSaved() async throws {
        let app = AppModel(repository: DemoRepository())
        await app.load()
        let retained = try XCTUnwrap(app.homeVideos.first)
        app.applyLocalChange { $0.bookmarkedVideoIds.insert(retained.id) }
        app.feedIds[.following] = [retained.id]

        await app.loadFeed(reset: true, kind: .following)

        XCTAssertTrue(app.homeVideos.contains { $0.id == retained.id })
        XCTAssertTrue(app.savedVideos.contains { $0.id == retained.id })
        XCTAssertFalse(app.feedIds[.following, default: []].contains(retained.id))
    }

    func testHomeFeedExcludesVideosRemovedByModeration() async throws {
        let app = AppModel(repository: DemoRepository())
        await app.load()
        let id = try XCTUnwrap(app.homeVideos.first?.id)
        let index = try XCTUnwrap(app.snapshot.videos.firstIndex { $0.id == id })
        app.applyLocalChange { $0.videos[index].status = .hidden }

        XCTAssertFalse(app.homeVideos.contains { $0.id == id })
    }

    func testBookmarkResponseCannotRestoreDeletedAccountState() async throws {
        let repository = DeferredRepository()
        let app = AppModel(repository: repository)
        await app.load()
        let video = try XCTUnwrap(app.homeVideos.first)
        let request = Task { await app.bookmark(video) }
        await repository.bookmarkGate.waitUntilStarted()

        try await repository.deleteAccount()
        await app.load()
        await repository.bookmarkGate.finish()
        await request.value

        XCTAssertNil(app.snapshot.userId)
        XCTAssertTrue(app.snapshot.bookmarkedVideoIds.isEmpty)
        XCTAssertNil(app.toast)
    }

    func testRefreshDoesNotDiscardSuccessfulBookmarkForTheSameMember() async throws {
        let repository = DeferredRepository(bookmarkBeforeCommit: true)
        let app = AppModel(repository: repository)
        await app.load()
        let video = try XCTUnwrap(app.homeVideos.first)
        let request = Task { await app.bookmark(video) }
        await repository.bookmarkGate.waitUntilStarted()

        await app.load()
        XCTAssertFalse(app.snapshot.bookmarkedVideoIds.contains(video.id))
        await repository.bookmarkGate.finish()
        await request.value

        XCTAssertTrue(app.snapshot.bookmarkedVideoIds.contains(video.id))
    }

    func testOlderRefreshCannotEraseABookmarkThatAlreadySucceeded() async throws {
        let delay = DeferredBootstrap()
        let repository = DeferredRepository(bootstrapDelay: delay)
        let app = AppModel(repository: repository)
        await app.load()
        let video = try XCTUnwrap(app.homeVideos.first)
        let gate = await delay.enqueue()
        let refresh = Task { await app.load() }
        await gate.waitUntilStarted()

        let save = Task { await app.bookmark(video) }
        await repository.bookmarkGate.waitUntilStarted()
        await repository.bookmarkGate.finish()
        await save.value
        XCTAssertTrue(app.snapshot.bookmarkedVideoIds.contains(video.id))
        await gate.finish()
        await refresh.value

        XCTAssertTrue(app.snapshot.bookmarkedVideoIds.contains(video.id))
        XCTAssertFalse(app.isLoading)
    }

    func testRefreshStopsRetryingAndKeepsNewerStateWhenWritesContinue() async throws {
        let delay = DeferredBootstrap()
        let repository = DeferredRepository(bootstrapDelay: delay)
        let app = AppModel(repository: repository)
        await app.load()
        let videos = Array(app.homeVideos.prefix(2))
        XCTAssertEqual(videos.count, 2)
        let gates = [await delay.enqueue(), await delay.enqueue()]
        let refresh = Task { await app.load() }

        for (gate, video) in zip(gates, videos) {
            await gate.waitUntilStarted()
            let save = Task { await app.bookmark(video) }
            await repository.bookmarkGate.waitUntilStarted()
            await repository.bookmarkGate.finish()
            await save.value
            await gate.finish()
        }
        await refresh.value
        let requests = await delay.requestCount

        XCTAssertTrue(Set(videos.map(\.id)).isSubset(of: app.snapshot.bookmarkedVideoIds))
        XCTAssertFalse(app.isLoading)
        XCTAssertEqual(requests, 3)
    }

    func testReadOnlyHydrationDoesNotPreventNewSnapshotFromCommitting() async throws {
        let delay = DeferredBootstrap()
        let repository = DeferredRepository(bootstrapDelay: delay)
        let app = AppModel(repository: repository)
        await app.load()
        let dog = try XCTUnwrap(app.snapshot.dogs.first)
        XCTAssertGreaterThan(app.unreadCount, 0)
        try await repository.base.markActivityRead()
        await delay.setOnRead { app.merge(dogs: [dog]) }

        await app.load()
        let requests = await delay.requestCount

        XCTAssertEqual(app.unreadCount, 0)
        XCTAssertEqual(requests, 2)
    }

    func testOlderVotingRefreshCannotUndoCompletedVote() async throws {
        let delay = DeferredBootstrap()
        let repository = DeferredRepository(bootstrapDelay: delay)
        let app = AppModel(repository: repository)
        await app.load()
        let dog = try XCTUnwrap(app.visibleDogs.first)
        let gate = await delay.enqueue()
        let refresh = Task { await app.refreshVoting() }
        await gate.waitUntilStarted()

        await app.vote(dog)
        let standings = app.snapshot.standings
        await gate.finish()
        await refresh.value

        XCTAssertEqual(app.snapshot.votedDogId, dog.id)
        XCTAssertEqual(app.snapshot.standings, standings)
    }

    func testOlderActivityRefreshCannotRestoreUnreadNotifications() async throws {
        let delay = DeferredBootstrap()
        let repository = DeferredRepository(bootstrapDelay: delay)
        let app = AppModel(repository: repository)
        await app.load()
        XCTAssertGreaterThan(app.unreadCount, 0)
        let gate = await delay.enqueue()
        let refresh = Task { await app.refreshActivity() }
        await gate.waitUntilStarted()

        await app.markRead()
        await gate.finish()
        await refresh.value

        XCTAssertEqual(app.unreadCount, 0)
    }

    func testOlderFeedCannotRestoreAnIdentitySentForReview() async throws {
        let delay = DeferredBootstrap()
        let repository = DeferredRepository(feedDelay: delay)
        let app = AppModel(repository: repository)
        await app.load()
        let dog = try XCTUnwrap(app.ownDogs.first)
        let gate = await delay.enqueue()
        let feed = Task { await app.loadFeed(reset: true) }
        await gate.waitUntilStarted()

        var draft = dog; draft.name = "Cabby Junior"
        let saved = try await repository.saveDog(draft)
        app.mergeLocal(dogs: [saved])
        await gate.finish()
        await feed.value

        XCTAssertEqual(app.snapshot.dogs.first { $0.id == dog.id }?.name, "Cabby Junior")
        XCTAssertEqual(app.snapshot.dogs.first { $0.id == dog.id }?.moderationStatus, .pending)
        XCTAssertFalse(app.homeVideos.contains { $0.dogId == dog.id })
        XCTAssertTrue(app.loadingFeeds.isEmpty)
    }

    func testUnfollowingOneDogKeepsOtherFollowedDogsInTheActiveFeed() async throws {
        let delay = DeferredBootstrap()
        let app = AppModel(repository: DeferredRepository(feedDelay: delay))
        await app.load()
        let mochi = try XCTUnwrap(app.snapshot.dogs.first { $0.name == "Mochi" })
        let milo = try XCTUnwrap(app.snapshot.dogs.first { $0.name == "Milo" })
        await app.follow(milo)
        app.feedKind = .following
        await app.loadFeed(reset: true)
        XCTAssertTrue(app.homeVideos.contains { $0.dogId == mochi.id })
        XCTAssertTrue(app.homeVideos.contains { $0.dogId == milo.id })
        let gate = await delay.enqueue()
        let oldPage = Task { await app.loadFeed(reset: true) }
        await gate.waitUntilStarted()
        await app.follow(mochi)
        await gate.finish()
        await oldPage.value
        XCTAssertFalse(app.homeVideos.contains { $0.dogId == mochi.id })
        XCTAssertTrue(app.homeVideos.contains { $0.dogId == milo.id })
    }

    func testPaginationRetriesAfterAConcurrentWrite() async throws {
        let delay = DeferredBootstrap()
        let app = AppModel(repository: DeferredRepository(feedDelay: delay))
        await app.load()
        let first = try XCTUnwrap(app.feedIds[.forYou]?.first)
        app.feedIds[.forYou] = [first]; app.nextOffsets[.forYou] = 1; app.exhausted.remove(.forYou)
        let gates = [await delay.enqueue(), await delay.enqueue()]
        let page = Task { await app.loadFeed() }
        for gate in gates {
            await gate.waitUntilStarted()
            await app.markRead()
            await gate.finish()
        }
        await page.value

        XCTAssertGreaterThan(app.homeVideos.count, 1)
        XCTAssertTrue(app.exhausted.contains(.forYou))
        XCTAssertTrue(app.loadingFeeds.isEmpty)
    }

    func testFailedPaginationKeepsPlaybackAvailableWithoutAModalError() async throws {
        let delay = DeferredBootstrap()
        let app = AppModel(repository: DeferredRepository(feedDelay: delay))
        await app.load()
        let first = try XCTUnwrap(app.feedIds[.forYou]?.first)
        app.feedIds[.forYou] = [first]; app.nextOffsets[.forYou] = 1; app.exhausted.remove(.forYou)
        let gate = await delay.enqueue()
        let page = Task { await app.loadFeed() }
        await gate.waitUntilStarted()
        await gate.finish(throwing: URLError(.notConnectedToInternet))
        await page.value

        XCTAssertEqual(app.homeVideos.map(\.id), [first])
        XCTAssertTrue(app.loadingFeeds.isEmpty)
        XCTAssertNil(app.errorMessage)
        XCTAssertNotNil(app.feedFailures[.forYou])
        await app.retryFeed()
        XCTAssertGreaterThan(app.homeVideos.count, 1)
        XCTAssertNil(app.feedFailures[.forYou])
    }

    func testCanceledFeedDoesNotShowAnError() async throws {
        let delay = DeferredBootstrap()
        let app = AppModel(repository: DeferredRepository(feedDelay: delay))
        await app.load()
        let gate = await delay.enqueue()
        let page = Task { await app.loadFeed(reset: true) }
        await gate.waitUntilStarted()
        await gate.finish(throwing: URLError(.cancelled))
        await page.value

        XCTAssertNil(app.errorMessage)
        XCTAssertTrue(app.loadingFeeds.isEmpty)
        XCTAssertNil(app.feedFailures[.forYou])
    }

    func testFailedBootstrapRetriesAccountAndCatalogTogether() async throws {
        let delay = DeferredBootstrap()
        let app = AppModel(repository: DeferredRepository(bootstrapDelay: delay))
        let gate = await delay.enqueue()
        let startup = Task { await app.load() }
        await gate.waitUntilStarted()
        await gate.finish(throwing: URLError(.notConnectedToInternet))
        await startup.value
        XCTAssertNotNil(app.feedFailures[.forYou])
        XCTAssertNil(app.snapshot.userId)
        app.errorMessage = nil

        await app.retryFeed()

        XCTAssertNotNil(app.snapshot.userId)
        XCTAssertFalse(app.homeVideos.isEmpty)
        XCTAssertNil(app.feedFailures[.forYou])
    }

    func testSuccessfulRefreshClearsAPaginationFailureFromDuringTheRefresh() async throws {
        let bootstrap = DeferredBootstrap(), feed = DeferredBootstrap()
        let app = AppModel(repository: DeferredRepository(bootstrapDelay: bootstrap, feedDelay: feed))
        await app.load()
        let bootGate = await bootstrap.enqueue(), feedGate = await feed.enqueue()
        let refresh = Task { await app.load() }
        await bootGate.waitUntilStarted()
        let page = Task { await app.loadFeed(reset: true) }
        await feedGate.waitUntilStarted()
        await feedGate.finish(throwing: URLError(.notConnectedToInternet))
        await page.value
        XCTAssertNotNil(app.feedFailures[.forYou])

        await bootGate.finish()
        await refresh.value

        XCTAssertNil(app.feedFailures[.forYou])
        XCTAssertFalse(app.homeVideos.isEmpty)
    }

    func testPageStartedDuringRefreshCannotOverwriteTheCommittedRefresh() async throws {
        let bootstrap = DeferredBootstrap(), feed = DeferredBootstrap()
        let repository = DeferredRepository(bootstrapDelay: bootstrap, feedDelay: feed)
        let app = AppModel(repository: repository)
        await app.load()
        let video = try XCTUnwrap(app.homeVideos.first)
        let bootGate = await bootstrap.enqueue(), feedGate = await feed.enqueue()
        let refresh = Task { await app.load() }
        await bootGate.waitUntilStarted()
        let page = Task { await app.loadFeed(reset: true) }
        await feedGate.waitUntilStarted()
        try await repository.base.setLike(videoId: video.id, liked: true)

        await bootGate.finish()
        await refresh.value
        XCTAssertEqual(app.snapshot.videos.first { $0.id == video.id }?.likeCount, video.likeCount + 1)
        await feedGate.finish()
        await page.value

        XCTAssertEqual(app.snapshot.videos.first { $0.id == video.id }?.likeCount, video.likeCount + 1)
        XCTAssertTrue(app.loadingFeeds.isEmpty)
    }
}
