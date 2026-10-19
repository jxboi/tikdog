import XCTest
import TikDogCore
@testable import TikDog

@MainActor final class CommentsViewModelTests: XCTestCase {
    func testSendingKeepsNewTextTypedWhileWaitingForResponse() async throws {
        let gate = RequestGate()
        let repository = DeferredRepository(commentGate: gate)
        let app = AppModel(repository: repository)
        await app.load()
        let video = try XCTUnwrap(app.homeVideos.first)
        let model = CommentsViewModel()
        model.draft = "First thought"

        let send = Task { await model.send(video: video, app: app) }
        await gate.waitUntilStarted()
        model.draft = "Another thought"
        await gate.finish()
        await send.value

        XCTAssertEqual(model.comments.last?.body, "First thought")
        XCTAssertEqual(model.draft, "Another thought")
        XCTAssertFalse(model.isSending)
    }

    func testSuccessfulReloadClearsPreviousError() async throws {
        let gate = RequestGate()
        var repository = DeferredRepository(commentsGate: gate)
        let snapshot = try await repository.bootstrap()
        let video = try XCTUnwrap(snapshot.videos.first)
        let model = CommentsViewModel()
        let load = Task { [repository] in await model.load(video: video, repository: repository) }
        await gate.waitUntilStarted()
        await gate.finish(throwing: TikDogError.unavailable)
        await load.value
        XCTAssertNotNil(model.error)

        repository.commentsGate = nil
        await model.load(video: video, repository: repository)

        XCTAssertNil(model.error)
        XCTAssertFalse(model.comments.isEmpty)
    }

    func testCanceledLoadDoesNotExposeAnError() async throws {
        let gate = RequestGate()
        let repository = DeferredRepository(commentsGate: gate)
        let snapshot = try await repository.bootstrap()
        let video = try XCTUnwrap(snapshot.videos.first)
        let model = CommentsViewModel()
        let load = Task { await model.load(video: video, repository: repository) }
        await gate.waitUntilStarted()
        load.cancel()
        await gate.finish(throwing: CancellationError())
        await load.value

        XCTAssertNil(model.error)
        XCTAssertFalse(model.isLoading)
    }

    func testRefreshCapturedBeforeSendCannotRemoveTheNewComment() async throws {
        let sendGate = RequestGate(), loadGate = RequestGate()
        let repository = DeferredRepository(commentGate: sendGate, commentsGate: loadGate, commentBeforeCommit: true)
        let app = AppModel(repository: repository)
        await app.load()
        let video = try XCTUnwrap(app.homeVideos.first)
        let model = CommentsViewModel()
        model.draft = "A brand new thought"
        let existing = await repository.base.comments(videoId: video.id)
        let send = Task { await model.send(video: video, app: app) }
        await sendGate.waitUntilStarted()
        let refresh = Task { await model.load(video: video, repository: repository) }
        await loadGate.waitUntilStarted()

        await sendGate.finish()
        await send.value
        await loadGate.finish()
        await refresh.value

        XCTAssertTrue(model.comments.contains { $0.body == "A brand new thought" })
        XCTAssertTrue(Set(existing.map(\.id)).isSubset(of: Set(model.comments.map(\.id))))
        XCTAssertFalse(model.isLoading)
        var immediate = repository; immediate.commentsGate = nil
        await model.load(video: video, repository: immediate)
        XCTAssertEqual(model.comments.filter { $0.body == "A brand new thought" }.count, 1)
        let posted = try XCTUnwrap(model.comments.first { $0.body == "A brand new thought" })
        try await repository.reportContent(kind: .comment, id: posted.id, reason: "inappropriate")
        await model.load(video: video, repository: immediate)
        XCTAssertFalse(model.comments.contains { $0.id == posted.id })
    }

}
