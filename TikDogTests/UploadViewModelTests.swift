import XCTest
import TikDogCore
@testable import TikDog

@MainActor final class UploadViewModelTests: XCTestCase {
    func testDeletedAccountDraftCannotReturnFromALateViewSave() async throws {
        var state = DemoContent.snapshot(); state.userId = UUID()
        let app = AppModel(repository: DemoRepository(initialSnapshot: state))
        await app.load()
        let store = try XCTUnwrap(app.accountUploadDraftStore)
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = UploadViewModel(draftStore: store)
        await model.choose(try movieCopy())
        await model.flushDraft()
        try await app.deleteAccount()
        await model.flushDraft(); model.cleanup()
        let draft = try await store.load()
        XCTAssertNil(draft)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))
    }

    func testSuccessfulSubmissionRemovesTheRecoverableDraft() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("submitted-draft-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UploadDraftStore(directory: directory.appendingPathComponent("Draft"))
        let app = AppModel(repository: DemoRepository(mediaDirectory: directory.appendingPathComponent("Published")))
        await app.load()
        let model = UploadViewModel(draftStore: store)
        await model.choose(try movieCopy())
        model.dogId = try XCTUnwrap(app.ownDogs.first?.id); model.caption = "A saved adventure"
        await model.flushDraft()
        let source = try XCTUnwrap(model.sourceURL)
        await model.publish(app: app)
        XCTAssertEqual(model.stage, .success)
        let draft = try await store.load()
        XCTAssertNil(draft)
        model.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(model.publishedVideo?.caption, "A saved adventure")
    }

    func testCorruptDraftCannotReferenceAnotherAccountDirectory() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("invalid-draft-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = directory.appendingPathComponent("Account")
        try FileManager.default.createDirectory(at: account, withIntermediateDirectories: true)
        let sentinel = directory.appendingPathComponent("other-account-video")
        try Data("private".utf8).write(to: sentinel)
        let draft = UploadDraft(id: UUID(), fileName: "..", caption: "Invalid", hashtags: "", trimStart: 0, trimEnd: 2, updatedAt: .now)
        try JSONEncoder().encode(draft).write(to: account.appendingPathComponent("draft.json"))
        let store = UploadDraftStore(directory: account)
        do { _ = try await store.load(); XCTFail("Parent paths must be rejected") } catch { }
        try await store.clear(revision: 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
    }

    func testDraftRestoresMediaEditsAndIdentityAfterModelRestart() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("draft-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let movie = try movieCopy()
        let store = UploadDraftStore(directory: directory)
        let model = UploadViewModel(draftStore: store)
        await model.choose(movie)
        model.caption = "Keep this adventure"; model.hashtags = "walkies cavapoo"
        model.dogId = DemoContent.dogIds[0]; model.trimStart = 0.4; model.trimEnd = 2.1
        await model.flushDraft()
        let durable = try XCTUnwrap(model.sourceURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: movie.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: durable.path))
        let saved = try await UploadDraftStore(directory: directory).load()
        model.cleanup()

        let restored = UploadViewModel(draftStore: store)
        await restored.configureDrafts(ownerId: DemoContent.ownerId, isDemo: true)
        XCTAssertEqual(restored.savedDraft?.id, saved?.id)
        await restored.continueDraft()
        XCTAssertEqual(restored.stage, .edit)
        XCTAssertEqual(restored.caption, "Keep this adventure")
        XCTAssertEqual(restored.hashtags, "walkies cavapoo")
        XCTAssertEqual(restored.dogId, DemoContent.dogIds[0])
        XCTAssertEqual(restored.trimStart, 0.4, accuracy: 0.01)
        XCTAssertEqual(restored.trimEnd, 2.1, accuracy: 0.01)
        XCTAssertNotNil(restored.player)
        restored.caption = "An edit after reopening"
        await restored.flushDraft()
        let afterRestart = try await UploadDraftStore(directory: directory).load()
        XCTAssertEqual(afterRestart?.caption, "An edit after reopening")
        await restored.discardDraft()
        XCTAssertFalse(FileManager.default.fileExists(atPath: durable.path))
    }

    func testClearedDraftCannotBeResurrectedByALateSave() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("draft-order-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let movie = try movieCopy()
        defer { try? FileManager.default.removeItem(at: movie) }
        let store = UploadDraftStore(directory: directory)
        let source = try await store.importMovie(movie)
        let draft = UploadDraft(id: UUID(), fileName: source.lastPathComponent, caption: "Old draft", hashtags: "", trimStart: 0, trimEnd: 2, updatedAt: .now)
        try await store.save(draft, revision: 1)
        try await store.clear(revision: 3)
        try await store.save(draft, revision: 2)
        let restored = try await store.load()
        XCTAssertNil(restored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertNotEqual(UploadDraftStore.accountDirectory(ownerId: DemoContent.ownerId, isDemo: false),
                          UploadDraftStore.accountDirectory(ownerId: DemoContent.otherOwnerId, isDemo: false))
        XCTAssertNotEqual(UploadDraftStore.accountDirectory(ownerId: DemoContent.ownerId, isDemo: true),
                          UploadDraftStore.accountDirectory(ownerId: DemoContent.ownerId, isDemo: false))
    }

    private func movieCopy() throws -> URL {
        let bundled = try XCTUnwrap(Bundle.main.url(forResource: "cabby", withExtension: "mp4"))
        let copy = URL.temporaryDirectory.appendingPathComponent("upload-test-\(UUID()).mp4")
        try FileManager.default.copyItem(at: bundled, to: copy)
        return copy
    }

    func testCleanupPreservesBorrowedMovieFile() async throws {
        let movie = try movieCopy()
        defer { try? FileManager.default.removeItem(at: movie) }
        let model = UploadViewModel()
        await model.choose(movie, ownsFile: false)
        XCTAssertEqual(model.stage, .edit)

        model.cleanup()

        XCTAssertTrue(FileManager.default.fileExists(atPath: movie.path))
        XCTAssertNil(model.player)
        XCTAssertNil(model.sourceURL)
    }

    func testCleanupRemovesOwnedImportedMovieFile() async throws {
        let movie = try movieCopy()
        defer { try? FileManager.default.removeItem(at: movie) }
        let model = UploadViewModel()
        await model.choose(movie)
        XCTAssertEqual(model.stage, .edit)
        XCTAssertGreaterThan(model.duration, 1)

        model.cleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: movie.path))
    }

    func testInvalidReplacementKeepsExistingDraftAndRemovesRejectedImport() async throws {
        let movie = try movieCopy()
        let invalid = URL.temporaryDirectory.appendingPathComponent("invalid-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: movie); try? FileManager.default.removeItem(at: invalid) }
        try Data("not a movie".utf8).write(to: invalid)
        let model = UploadViewModel()
        await model.choose(movie)
        model.caption = "Keep this story"

        await model.choose(invalid)

        XCTAssertEqual(model.stage, .edit)
        XCTAssertEqual(model.sourceURL, movie)
        XCTAssertEqual(model.caption, "Keep this story")
        XCTAssertNotNil(model.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalid.path))
        model.cleanup()
    }

    func testPublishResponseCannotRestoreContentAfterAccountDeletion() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("publish-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = RequestGate()
        let repository = DeferredRepository(base: DemoRepository(mediaDirectory: directory), publishGate: gate)
        let app = AppModel(repository: repository)
        await app.load()
        let dog = try XCTUnwrap(app.ownDogs.first)
        let movie = try movieCopy()
        let model = UploadViewModel()
        await model.choose(movie)
        model.dogId = dog.id; model.caption = "An old account's adventure"
        let publish = Task { await model.publish(app: app) }
        await gate.waitUntilStarted()

        try await repository.deleteAccount()
        await app.load()
        await gate.finish()
        await publish.value

        XCTAssertNil(app.snapshot.userId)
        XCTAssertFalse(app.snapshot.videos.contains { $0.caption == "An old account's adventure" })
        XCTAssertNil(model.publishedVideo)
        XCTAssertNotEqual(model.stage, .success)
        model.cleanup()
    }
}
