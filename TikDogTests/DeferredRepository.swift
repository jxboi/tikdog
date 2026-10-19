import Foundation
import TikDogCore

actor RequestGate {
    private var response: CheckedContinuation<Void, any Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async throws {
        try await withCheckedThrowingContinuation { response in
            self.response = response
            for waiter in waiters { waiter.resume() }
            waiters = []
        }
    }
    func waitUntilStarted() async {
        if response != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func finish(throwing error: (any Error)? = nil) {
        if let error { response?.resume(throwing: error) }
        else { response?.resume() }
        response = nil
    }
}

struct DeferredRepository: TikDogRepository {
    var base = DemoRepository()
    let bookmarkGate = RequestGate()
    let isDemo = true
    var commentGate: RequestGate?
    var commentsGate: RequestGate?
    var bookmarkBeforeCommit = false
    var commentBeforeCommit = false
    var profileResponses: DeferredProfiles?
    var bootstrapDelay: DeferredBootstrap?
    var publishGate: RequestGate?
    var feedDelay: DeferredBootstrap?
    var profileDelay: DeferredBootstrap?
    var deleteGate: RequestGate?

    func accountState() async throws -> AccountState { await base.accountState() }
    func acceptTerms() async throws { await base.acceptTerms() }
    func reportContent(kind: ReportTarget, id: UUID, reason: String) async throws { try await base.reportContent(kind: kind, id: id, reason: reason) }
    func blockedAccounts() async throws -> [BlockedAccount] { await base.blockedAccounts() }
    func unblock(ownerId: UUID) async throws { try await base.unblock(ownerId: ownerId) }
    func bootstrap() async throws -> AppSnapshot {
        let snapshot = try await base.bootstrap()
        try await bootstrapDelay?.holdNext()
        return snapshot
    }
    func feed(kind: FeedKind, offset: Int, limit: Int) async throws -> FeedPage {
        let page = await base.feed(kind: kind, offset: offset, limit: limit)
        try await feedDelay?.holdNext()
        return page
    }
    func discover(query: String) async throws -> [Dog] { await base.discover(query: query) }
    func profile(dogId: UUID) async throws -> ProfilePage {
        if let profileResponses { return try await profileResponses.load() }
        let page = try await base.profile(dogId: dogId)
        try await profileDelay?.holdNext()
        return page
    }
    func setLike(videoId: UUID, liked: Bool) async throws { try await base.setLike(videoId: videoId, liked: liked) }
    func setBookmark(videoId: UUID, saved: Bool) async throws {
        if bookmarkBeforeCommit { try await bookmarkGate.suspend() }
        try await base.setBookmark(videoId: videoId, saved: saved)
        if !bookmarkBeforeCommit { try await bookmarkGate.suspend() }
    }
    func setFollow(dogId: UUID, following: Bool) async throws { try await base.setFollow(dogId: dogId, following: following) }
    func comments(videoId: UUID) async throws -> [DogComment] {
        let comments = await base.comments(videoId: videoId)
        try await commentsGate?.suspend()
        return comments
    }
    func addComment(videoId: UUID, body: String) async throws -> DogComment {
        if commentBeforeCommit { try await commentGate?.suspend() }
        let comment = try await base.addComment(videoId: videoId, body: body)
        if !commentBeforeCommit { try await commentGate?.suspend() }
        return comment
    }
    func saveDog(_ dog: Dog) async throws -> Dog { try await base.saveDog(dog) }
    func uploadAvatar(file: URL) async throws -> String { try await base.uploadAvatar(file: file) }
    func publish(_ video: Video, file: URL, thumbnail: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> Video {
        let published = try await base.publish(video, file: file, thumbnail: thumbnail, progress: progress)
        try await publishGate?.suspend()
        return published
    }
    func vote(dogId: UUID) async throws -> [DailyStanding] { try await base.vote(dogId: dogId) }
    func report(videoId: UUID, reason: String) async throws { try await base.report(videoId: videoId, reason: reason) }
    func block(ownerId: UUID) async throws { try await base.block(ownerId: ownerId) }
    func markActivityRead() async throws { try await base.markActivityRead() }
    func deleteVideo(id: UUID) async throws { try await base.deleteVideo(id: id) }
    func deleteAccount() async throws { try await deleteGate?.suspend(); try await base.deleteAccount() }
}

actor DeferredProfiles {
    let firstGate = RequestGate()
    let secondGate = RequestGate()
    private let pages: [ProfilePage]
    private var next = 0

    init(pages: [ProfilePage]) { self.pages = pages }
    func load() async throws -> ProfilePage {
        let index = next; next += 1
        let page = pages[index]
        try await (index == 0 ? firstGate : secondGate).suspend()
        return page
    }
}

actor DeferredBootstrap {
    private var gates: [RequestGate] = []
    private(set) var requestCount = 0
    private var onRead: (@MainActor @Sendable () -> Void)?

    func setOnRead(_ action: @escaping @MainActor @Sendable () -> Void) { onRead = action }
    func enqueue() -> RequestGate {
        let gate = RequestGate(); gates.append(gate)
        return gate
    }
    func holdNext() async throws {
        requestCount += 1
        if let onRead { await onRead() }
        guard !gates.isEmpty else { return }
        let gate = gates.removeFirst()
        try await gate.suspend()
    }
}
