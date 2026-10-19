import XCTest
import SwiftUI
import TikDogCore
@testable import TikDog

@MainActor final class FeedRecoveryViewTests: XCTestCase {
    func testFailedStartupOffersRetryInsteadOfAnEmptyCommunity() async throws {
        let delay = DeferredBootstrap()
        let app = AppModel(repository: DeferredRepository(bootstrapDelay: delay))
        let gate = await delay.enqueue()
        let startup = Task { await app.load() }
        await gate.waitUntilStarted()
        await gate.finish(throwing: URLError(.notConnectedToInternet))
        await startup.value
        XCTAssertTrue(app.homeVideos.isEmpty)
        XCTAssertNotNil(app.feedFailures[.forYou])

        try await capture(app, name: "Offline-startup-retry")

        XCTAssertNotNil(app.feedFailures[.forYou])
    }

    func testFailedPaginationOffersRetryOverTheRetainedVideos() async throws {
        let delay = DeferredBootstrap()
        let app = AppModel(repository: DeferredRepository(feedDelay: delay))
        await app.load()
        let ids = Array(try XCTUnwrap(app.feedIds[.forYou]).prefix(4))
        app.feedIds[.forYou] = ids; app.nextOffsets[.forYou] = 4; app.exhausted.remove(.forYou)
        let gate = await delay.enqueue()
        let page = Task { await app.loadFeed() }
        await gate.waitUntilStarted()
        await gate.finish(throwing: URLError(.notConnectedToInternet))
        await page.value
        XCTAssertEqual(app.homeVideos.map(\.id), ids)
        XCTAssertNil(app.errorMessage)

        try await capture(app, name: "Offline-pagination-retry")

        XCTAssertEqual(app.homeVideos.map(\.id), ids)
        XCTAssertNotNil(app.feedFailures[.forYou])
    }

    func testRefreshAtTheLastLoadedClipAutomaticallyContinuesPagination() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("feed-continuation-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var snapshot = DemoContent.snapshot()
        for index in 1...4 {
            var extra = snapshot.videos[0]
            extra.id = UUID(); extra.caption = "Another adventure \(index)"
            extra.likeCount = 0; extra.commentCount = 0; extra.viewCount = 0; extra.createdAt = .distantPast
            snapshot.videos.append(extra)
        }
        struct Seed: Encodable {
            let state: AppSnapshot
            let comments: [UUID: [DogComment]] = [:]
            let reports: Set<UUID> = []
        }
        let file = directory.appendingPathComponent("demo.json")
        try JSONEncoder().encode(Seed(state: snapshot)).write(to: file)
        let delay = DeferredBootstrap()
        let app = AppModel(repository: DeferredRepository(base: DemoRepository(persistenceURL: file), bootstrapDelay: delay))
        await app.load()
        XCTAssertEqual(app.snapshot.videos.count, 12)
        XCTAssertEqual(app.homeVideos.count, 8)
        let last = try XCTUnwrap(app.homeVideos.last?.id)
        let gate = await delay.enqueue()
        let refresh = Task { await app.load() }
        await gate.waitUntilStarted()

        try await capture(app, name: "Refresh-continues-pagination", initialVideo: last) {
            await gate.finish()
            await refresh.value
            for _ in 0..<100 {
                if app.homeVideos.count == 12 { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertEqual(app.homeVideos.count, 12)
        }
    }

    private func capture(_ app: AppModel, name: String, initialVideo: UUID? = nil, whileVisible: (@MainActor () async throws -> Void)? = nil) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let original = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let controller = UIHostingController(rootView: FeedView(initialVideo: initialVideo).environment(app).environment(\.scenePhase, .active).preferredColorScheme(.dark))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; original?.makeKey() }
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        try await whileVisible?()
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
