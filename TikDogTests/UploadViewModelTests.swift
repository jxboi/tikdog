import XCTest
import TikDogCore
@testable import TikDog

@MainActor final class UploadViewModelTests: XCTestCase {
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
