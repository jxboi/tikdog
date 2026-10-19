import XCTest
import AVFoundation
import TikDogCore
@testable import TikDog

@MainActor final class PlaybackControllerTests: XCTestCase {
    func testRenewedMediaURLPreservesPausedPlaybackPosition() async throws {
        try await verifyPausedPositionAfterRenewal(replacements: 1)
    }

    func testConsecutiveRenewalsPreserveThePendingPlaybackPosition() async throws {
        try await verifyPausedPositionAfterRenewal(replacements: 2)
    }

    private func verifyPausedPositionAfterRenewal(replacements: Int) async throws {
        let source = try XCTUnwrap(Bundle.main.url(forResource: "cabby", withExtension: "mp4"))
        let folder = URL.temporaryDirectory.appendingPathComponent("renewals-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let paths = try (0..<replacements).map { index in
            let copy = folder.appendingPathComponent("\(index).mp4")
            try FileManager.default.copyItem(at: source, to: copy)
            return copy
        }
        var video = Video(dogId: UUID(), caption: "A little adventure", mediaPath: source.absoluteString, duration: 3.4)
        let controller = PlaybackController()
        defer { controller.stop() }
        controller.activate(video, in: [video])
        controller.togglePause()
        let initial = try XCTUnwrap(controller.player(for: video.id))
        for _ in 0..<100 {
            if initial.currentItem?.status == .readyToPlay { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(initial.currentItem?.status, .readyToPlay)
        let positioned = await initial.seek(to: CMTime(seconds: 1.2, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        XCTAssertTrue(positioned)
        XCTAssertEqual(initial.currentTime().seconds, 1.2, accuracy: 0.05)

        for path in paths {
            video.playbackPath = path.absoluteString
            controller.activate(video, in: [video])
        }
        let replacement = try XCTUnwrap(controller.player(for: video.id))
        XCTAssertFalse(initial === replacement)
        for _ in 0..<100 {
            if replacement.currentItem?.status == .readyToPlay && abs(replacement.currentTime().seconds - 1.2) < 0.05 { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertTrue(controller.isPaused)
        XCTAssertEqual(replacement.rate, 0)
        XCTAssertEqual(replacement.currentTime().seconds, 1.2, accuracy: 0.05)
    }
}
