import Foundation

public enum DemoContent {
    public static let ownerId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    public static let otherOwnerId = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    public static let dogIds = (1...4).map { UUID(uuidString: "00000000-0000-4000-8000-00000000000\($0)")! }
    public static func snapshot(now: Date = .now) -> AppSnapshot {
        let dogs = [
            Dog(id: dogIds[0], ownerId: ownerId, name: "Cabby", breed: "Cavapoo", birthday: "2024-12-18", bio: "Small dog, big personality.\nProfessional heart stealer & sock collector.", avatarPath: "cabby-avatar.jpg", followerCount: 24800, isFeatured: true),
            Dog(id: dogIds[1], ownerId: otherOwnerId, name: "Mochi", breed: "Shiba Inu", birthday: "2023-04-12", bio: "A little dramatic. A lot of fluff. 🍡", avatarPath: "mochi-avatar.jpg", followerCount: 860, isFeatured: true),
            Dog(id: dogIds[2], ownerId: otherOwnerId, name: "Milo", breed: "Golden Retriever", birthday: "2022-08-03", bio: "Every day is the best day ever. 🎾", avatarPath: "milo-avatar.jpg", followerCount: 12500),
            Dog(id: dogIds[3], ownerId: otherOwnerId, name: "Luna", breed: "Corgi", birthday: "2024-02-14", bio: "Short legs. Tall ambitions. 🌙", avatarPath: "luna-avatar.jpg", followerCount: 740)
        ]
        let captions = ["POV: you said ‘walk’ and now there's no going back 🐾", "My morning routine? Be adorable. Repeat.", "No thoughts. Just golden retriever energy. ☀️", "Taking my very important little walk.", "The tiniest adventure buddy, reporting for duty.", "Sorry, I can't. I have very important sniffing to do.", "Found my happy place. It's everywhere with you.", "Built low. Aiming high. ✨"]
        let tags = [["cavapoo", "dogsoftikdog", "walkies"], ["shibainu", "mochimood"], ["goldenretriever", "goodboy"], ["corgilife", "littlelegs"]]
        let assets = ["cabby", "mochi", "milo", "luna"]
        let videos = (0..<8).map { i in
            Video(id: UUID(uuidString: String(format: "10000000-0000-4000-8000-%012d", i + 1))!, dogId: dogIds[i % 4], caption: captions[i], hashtags: tags[i % 4], mediaPath: "\(assets[i % 4]).mp4", thumbnailPath: "\(assets[i % 4]).jpg", duration: [3.4, 10.01, 9.476, 10.01][i % 4], likeCount: [1240, 382, 2840, 729, 684, 126, 592, 87][i], commentCount: [24, 12, 83, 31, 18, 8, 20, 4][i], viewCount: 18000 - i * 1700, createdAt: now.addingTimeInterval(Double(-i) * 5400))
        }
        return AppSnapshot(dogs: dogs, videos: videos, followingDogIds: [dogIds[1]], activities: [
            ActivityItem(kind: "milestone", dogId: dogIds[0], message: "Cabby is making tails wag! Your video reached 1,000 likes.", createdAt: now.addingTimeInterval(-1200)),
            ActivityItem(kind: "follow", dogId: dogIds[1], message: "Mochi's person started following Cabby.", createdAt: now.addingTimeInterval(-3600)),
            ActivityItem(kind: "comment", dogId: dogIds[2], videoId: videos[0].id, message: "Milo's person: That little face! 🥹", createdAt: now.addingTimeInterval(-7200))
        ], standings: zip(dogIds, [128, 96, 112, 84]).enumerated().map { DailyStanding(dogId: $0.element.0, votes: $0.element.1, wins: [3, 1, 5, 2][$0.offset]) }, voteDay: ContentRules.utcDay(now), userId: ownerId, displayName: "Cabby's person")
    }
}

public actor DemoRepository: TikDogRepository {
    public nonisolated let isDemo = true
    private var state: AppSnapshot
    private var commentStore: [UUID: [DogComment]] = [:]
    private var reports: Set<UUID> = []
    private let persistenceURL: URL?
    private let mediaDirectory: URL?

    public init(persistenceURL: URL? = nil, mediaDirectory: URL? = nil, initialSnapshot: AppSnapshot? = nil) {
        self.persistenceURL = persistenceURL; self.mediaDirectory = mediaDirectory
        if let persistenceURL, let data = try? Data(contentsOf: persistenceURL), let saved = try? JSONDecoder().decode(Persisted.self, from: data) {
            self.state = saved.state; self.commentStore = saved.comments; self.reports = saved.reports
        } else { self.state = initialSnapshot ?? DemoContent.snapshot() }
    }
    private struct Persisted: Codable { var state: AppSnapshot; var comments: [UUID: [DogComment]]; var reports: Set<UUID> }
    private func persist() throws {
        guard let persistenceURL else { return }
        try FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Persisted(state: state, comments: commentStore, reports: reports))
        try data.write(to: persistenceURL, options: .atomic)
    }
    private func rollover() {
        let today = ContentRules.utcDay()
        guard state.voteDay != today else { return }
        let winner = state.voteDay < today ? state.standings.filter { $0.votes > 0 }.sorted {
            $0.votes == $1.votes ? $0.dogId.uuidString < $1.dogId.uuidString : $0.votes > $1.votes
        }.first?.dogId : nil
        state.voteDay = today; state.votedDogId = nil
        state.standings = state.standings.map { DailyStanding(dogId: $0.dogId, votes: 0, wins: $0.wins + ($0.dogId == winner ? 1 : 0)) }
    }
    public func accountState() -> AccountState { AccountState(termsVersion: CommunityTerms.version) }
    public func acceptTerms() {}
    public func blockedAccounts() -> [BlockedAccount] {
        state.blockedOwnerIds.map { id in BlockedAccount(id: id, name: state.dogs.first { $0.ownerId == id }?.name ?? "Dog person") }
    }
    public func unblock(ownerId: UUID) throws { state.blockedOwnerIds.remove(ownerId); try persist() }
    public func reportContent(kind: ReportTarget, id: UUID, reason: String) throws { reports.insert(id); try persist() }
    public func bootstrap() throws -> AppSnapshot {
        rollover()
        var visible = state
        visible.dogs = state.dogs.filter { !state.blockedOwnerIds.contains($0.ownerId) && !reports.contains($0.id) }
        let dogIds = Set(visible.dogs.map(\.id))
        visible.videos = state.videos.filter { dogIds.contains($0.dogId) && !reports.contains($0.id) }
        visible.standings = state.standings.filter { dogIds.contains($0.dogId) }
        visible.activities = state.activities.filter { $0.dogId == nil || dogIds.contains($0.dogId!) }
        return visible
    }
    public func feed(kind: FeedKind, offset: Int, limit: Int) -> FeedPage {
        let visibleDogs = state.dogs.filter { $0.moderationStatus == .ready && !state.blockedOwnerIds.contains($0.ownerId) && !reports.contains($0.id) }
        let dogIds = Set(visibleDogs.map(\.id))
        let ranked = state.videos.filter { $0.moderationStatus == .ready && dogIds.contains($0.dogId) && !reports.contains($0.id) && (kind == .forYou || state.followingDogIds.contains($0.dogId)) }.sorted { lhs, rhs in
            if kind == .following { return lhs.createdAt > rhs.createdAt }
            let left = FeedRanking.score(lhs, followers: visibleDogs.first { $0.id == lhs.dogId }?.followerCount ?? 0)
            let right = FeedRanking.score(rhs, followers: visibleDogs.first { $0.id == rhs.dogId }?.followerCount ?? 0)
            return left == right ? lhs.id.uuidString < rhs.id.uuidString : left > right
        }
        let start = min(max(0, offset), ranked.count), end = min(start + max(1, limit), ranked.count)
        return FeedPage(videos: Array(ranked[start..<end]), dogs: visibleDogs, nextOffset: end < ranked.count ? end : nil)
    }
    public func discover(query: String) -> [Dog] {
        state.dogs.filter { $0.moderationStatus == .ready && !reports.contains($0.id) && !state.blockedOwnerIds.contains($0.ownerId) && (query.isEmpty || "\($0.name) \($0.breed)".localizedCaseInsensitiveContains(query)) }
    }
    public func profile(dogId: UUID) throws -> ProfilePage {
        guard let dog = state.dogs.first(where: { $0.id == dogId && !reports.contains($0.id) && !state.blockedOwnerIds.contains($0.ownerId) && !reports.contains($0.id) }) else { throw TikDogError.unavailable }
        return ProfilePage(dog: dog, videos: state.videos.filter { $0.dogId == dogId && !reports.contains($0.id) }.sorted { $0.createdAt > $1.createdAt })
    }
    public func setLike(videoId: UUID, liked: Bool) throws {
        guard let i = state.videos.firstIndex(where: { $0.id == videoId }) else { throw TikDogError.unavailable }
        if liked != state.likedVideoIds.contains(videoId) {
            if liked { state.likedVideoIds.insert(videoId) } else { state.likedVideoIds.remove(videoId) }
            state.videos[i].likeCount = max(0, state.videos[i].likeCount + (liked ? 1 : -1)); try persist()
        }
    }
    public func setBookmark(videoId: UUID, saved: Bool) throws {
        if saved { state.bookmarkedVideoIds.insert(videoId) } else { state.bookmarkedVideoIds.remove(videoId) }; try persist()
    }
    public func setFollow(dogId: UUID, following: Bool) throws {
        guard let i = state.dogs.firstIndex(where: { $0.id == dogId }) else { throw TikDogError.unavailable }
        guard state.dogs[i].ownerId != state.userId else { throw TikDogError.invalidInput("Your dog is already part of your pack.") }
        if following != state.followingDogIds.contains(dogId) {
            if following { state.followingDogIds.insert(dogId) } else { state.followingDogIds.remove(dogId) }
            state.dogs[i].followerCount = max(0, state.dogs[i].followerCount + (following ? 1 : -1)); try persist()
        }
    }
    public func comments(videoId: UUID) -> [DogComment] {
        if let comments = commentStore[videoId] { return comments.filter { !state.blockedOwnerIds.contains($0.userId) && !reports.contains($0.id) } }
        if reports.contains(UUID(uuidString: "30000000-0000-4000-8000-000000000001")!) || state.blockedOwnerIds.contains(DemoContent.otherOwnerId) { return [] }
        return [DogComment(id: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!, videoId: videoId, userId: DemoContent.otherOwnerId, author: "Mochi's person", body: "The internet was made for this little face 🥹", createdAt: .now.addingTimeInterval(-1800))]
    }
    public func addComment(videoId: UUID, body: String) throws -> DogComment {
        let clean = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 500 else { throw TikDogError.invalidInput("Write a comment between 1 and 500 characters.") }
        guard let userId = state.userId, let i = state.videos.firstIndex(where: { $0.id == videoId }) else { throw TikDogError.signInRequired }
        var comment = DogComment(videoId: videoId, userId: userId, author: state.displayName, body: clean)
        comment.status = .pending
        var all = comments(videoId: videoId); all.append(comment); commentStore[videoId] = all
        _ = i; try persist(); return comment
    }
    public func saveDog(_ input: Dog) throws -> Dog {
        var dog = input; dog.status = .pending
        try ContentRules.validateDog(name: dog.name, breed: dog.breed, bio: dog.bio)
        guard dog.ownerId == state.userId else { throw TikDogError.signInRequired }
        if let i = state.dogs.firstIndex(where: { $0.id == dog.id }) {
            guard state.dogs[i].ownerId == state.userId else { throw TikDogError.signInRequired }; state.dogs[i] = dog
        } else { state.dogs.append(dog); state.standings.append(DailyStanding(dogId: dog.id, votes: 0)) }
        try persist(); return dog
    }
    public func uploadAvatar(file: URL) throws -> String {
        guard let mediaDirectory else { throw TikDogError.unavailable }
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let destination = mediaDirectory.appendingPathComponent("avatar-\(UUID()).jpg")
        try FileManager.default.copyItem(at: file, to: destination); return destination.absoluteString
    }
    public func publish(_ video: Video, file: URL, thumbnail: URL, progress: @escaping @Sendable (Double) -> Void) throws -> Video {
        try ContentRules.validateVideo(caption: video.caption, duration: video.duration)
        guard state.dogs.contains(where: { $0.id == video.dogId && $0.ownerId == state.userId }), let mediaDirectory else { throw TikDogError.signInRequired }
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let destination = mediaDirectory.appendingPathComponent("\(video.id).mp4")
        let cover = mediaDirectory.appendingPathComponent("\(video.id).jpg")
        progress(0.15)
        try FileManager.default.copyItem(at: file, to: destination)
        do { try FileManager.default.copyItem(at: thumbnail, to: cover) } catch { try? FileManager.default.removeItem(at: destination); throw error }
        var published = video; published.status = .pending; published.mediaPath = destination.absoluteString; published.thumbnailPath = cover.absoluteString
        state.videos.insert(published, at: 0)
        do { try persist() } catch { state.videos.removeAll { $0.id == published.id }; try? FileManager.default.removeItem(at: destination); try? FileManager.default.removeItem(at: cover); throw error }
        progress(1); return published
    }
    public func vote(dogId: UUID) throws -> [DailyStanding] {
        rollover(); guard state.votedDogId == nil else { throw TikDogError.alreadyVoted }
        guard let i = state.standings.firstIndex(where: { $0.dogId == dogId }) else { throw TikDogError.unavailable }
        state.votedDogId = dogId; state.standings[i].votes += 1; try persist(); return state.standings
    }
    public func report(videoId: UUID, reason: String) throws { reports.insert(videoId); try persist() }
    public func block(ownerId: UUID) throws {
        guard ownerId != state.userId else { throw TikDogError.invalidInput("You can't block your own account.") }
        let dogIds = Set(state.dogs.filter { $0.ownerId == ownerId }.map(\.id))
        state.followingDogIds.subtract(dogIds)
        state.blockedOwnerIds.insert(ownerId); try persist()
    }
    public func markActivityRead() throws { for i in state.activities.indices { state.activities[i].isRead = true }; try persist() }
    public func deleteVideo(id: UUID) throws {
        guard let video = state.videos.first(where: { $0.id == id }), state.dogs.contains(where: { $0.id == video.dogId && $0.ownerId == state.userId }) else { throw TikDogError.signInRequired }
        state.videos.removeAll { $0.id == id }; state.likedVideoIds.remove(id); state.bookmarkedVideoIds.remove(id); commentStore[id] = nil; try persist()
        if let url = URL(string: video.mediaPath), url.isFileURL { try? FileManager.default.removeItem(at: url) }
        if let url = URL(string: video.thumbnailPath), url.isFileURL { try? FileManager.default.removeItem(at: url) }
    }
    public func deleteAccount() throws {
        let deletingUser = state.userId
        let ownedDogs = state.dogs.filter { $0.ownerId == deletingUser }
        let ids = Set(ownedDogs.map(\.id))
        for id in state.likedVideoIds { if let i = state.videos.firstIndex(where: { $0.id == id }) { state.videos[i].likeCount = max(0, state.videos[i].likeCount - 1) } }
        for id in state.followingDogIds { if let i = state.dogs.firstIndex(where: { $0.id == id }) { state.dogs[i].followerCount = max(0, state.dogs[i].followerCount - 1) } }
        for (videoId, comments) in commentStore {
            let remaining = comments.filter { $0.userId != deletingUser }
            if let i = state.videos.firstIndex(where: { $0.id == videoId }) { state.videos[i].commentCount = max(0, state.videos[i].commentCount - (comments.filter { $0.userId == deletingUser && $0.moderationStatus == .ready }.count)) }
            commentStore[videoId] = remaining
        }
        if let voted = state.votedDogId, let i = state.standings.firstIndex(where: { $0.dogId == voted }) { state.standings[i].votes = max(0,state.standings[i].votes-1) }
        state.votedDogId = nil; state.blockedOwnerIds = []; reports = []
        for dog in ownedDogs { if let url = URL(string: dog.avatarPath), url.isFileURL { try? FileManager.default.removeItem(at: url) } }
        for video in state.videos where ids.contains(video.dogId) { try deleteVideo(id: video.id) }
        state.dogs.removeAll { ids.contains($0.id) }; state.userId = nil; state.followingDogIds = []; state.likedVideoIds = []; state.bookmarkedVideoIds = []; state.activities = []; try persist()
    }
}
