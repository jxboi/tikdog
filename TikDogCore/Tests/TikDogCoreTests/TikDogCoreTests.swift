import Foundation
import Testing
@testable import TikDogCore

struct TikDogCoreTests {
    @Test func hashtagNormalizationAndLimits() {
        #expect(ContentRules.hashtags(from: "#Cavapoo #cavapoo, Walkies #Good_Dog") == ["cavapoo", "walkies", "good_dog"])
        #expect(ContentRules.hashtags(from: (1...15).map { "tag\($0)" }.joined(separator: " ")).count == 8)
    }
    @Test func validatesDogAndClipBoundaries() throws {
        try ContentRules.validateDog(name: "Cabby", breed: "Cavapoo", bio: "A very good dog")
        #expect(throws: TikDogError.self) { try ContentRules.validateDog(name: "   ", breed: "Cavapoo", bio: "") }
        for duration in [0, -1, Double.infinity, Double.nan, 61] {
            #expect(throws: TikDogError.self) { try ContentRules.validateVideo(caption: "", duration: duration) }
        }
        try ContentRules.validateVideo(caption: "", duration: 1)
        try ContentRules.validateVideo(caption: "", duration: 60)
    }
    @Test func rankingBalancesRecencyAndSmallerCreators() {
        let dog = UUID(); let now = Date.now
        let recent = Video(dogId: dog, caption: "", mediaPath: "", likeCount: 10, createdAt: now)
        let stale = Video(dogId: dog, caption: "", mediaPath: "", likeCount: 10, createdAt: now.addingTimeInterval(-86400))
        #expect(FeedRanking.score(recent, followers: 5000, now: now) > FeedRanking.score(stale, followers: 5000, now: now))
        #expect(FeedRanking.score(recent, followers: 100, now: now) > FeedRanking.score(recent, followers: 5000, now: now))
    }
    @Test func likeAndFollowAreIdempotent() async throws {
        let repo = DemoRepository(); let initial = try await repo.bootstrap(); let video = initial.videos[0]
        try await repo.setLike(videoId: video.id, liked: true); try await repo.setLike(videoId: video.id, liked: true)
        var updated = try await repo.bootstrap()
        #expect(updated.videos[0].likeCount == video.likeCount + 1)
        try await repo.setLike(videoId: video.id, liked: false); try await repo.setLike(videoId: video.id, liked: false)
        updated = try await repo.bootstrap(); #expect(updated.videos[0].likeCount == video.likeCount)
        let dog = initial.dogs[3]
        try await repo.setFollow(dogId: dog.id, following: true); try await repo.setFollow(dogId: dog.id, following: true)
        updated = try await repo.bootstrap(); #expect(updated.dogs[3].followerCount == dog.followerCount + 1)
        await #expect(throws: TikDogError.self) { try await repo.setFollow(dogId: initial.dogs[0].id, following: true) }
    }
    @Test func followingPaginationAndBlocking() async throws {
        let repo = DemoRepository(); let state = try await repo.bootstrap()
        let page = await repo.feed(kind: .following, offset: 0, limit: 1)
        #expect(page.videos.count == 1); #expect(page.nextOffset == 1)
        #expect(page.videos.allSatisfy { state.followingDogIds.contains($0.dogId) })
        let next = await repo.feed(kind: .following, offset: page.nextOffset!, limit: 1)
        #expect(next.videos.first?.id != page.videos.first?.id); #expect(next.nextOffset == nil)
        try await repo.block(ownerId: DemoContent.otherOwnerId)
        let filtered = await repo.feed(kind: .forYou, offset: 0, limit: 30)
        #expect(filtered.videos.allSatisfy { $0.dogId == DemoContent.dogIds[0] })
        #expect(await repo.discover(query: "Shiba").isEmpty)
    }
    @Test func commentsVotesAndBookmarksSurviveRelaunch() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent("TikDogTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("demo.json")
        let repo = DemoRepository(persistenceURL: file); let initial = try await repo.bootstrap(); let video = initial.videos[0]
        let comment = try await repo.addComment(videoId: video.id, body: "  Good dog!  ")
        #expect(comment.body == "Good dog!")
        try await repo.setBookmark(videoId: video.id, saved: true)
        let standings = try await repo.vote(dogId: initial.dogs[0].id)
        #expect(standings[0].votes == initial.standings[0].votes + 1)
        await #expect(throws: TikDogError.self) { try await repo.vote(dogId: initial.dogs[1].id) }
        let restored = DemoRepository(persistenceURL: file)
        let state = try await restored.bootstrap()
        #expect(state.bookmarkedVideoIds.contains(video.id)); #expect(state.votedDogId == initial.dogs[0].id)
        #expect(await restored.comments(videoId: video.id).contains { $0.body == "Good dog!" })
    }
    @Test func completedDemoVotingDayAwardsOneDeterministicWinner() async throws {
        struct SavedDemo: Encodable {
            var state: AppSnapshot
            var comments: [UUID: [DogComment]] = [:]
            var reports: Set<UUID> = []
        }
        let folder = URL.temporaryDirectory.appendingPathComponent("TikDogVoteRollover-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        var state = DemoContent.snapshot(now: .now.addingTimeInterval(-86400))
        state.votedDogId = DemoContent.dogIds[1]
        state.standings = [
            DailyStanding(dogId: DemoContent.dogIds[1], votes: 7, wins: 1),
            DailyStanding(dogId: DemoContent.dogIds[0], votes: 7, wins: 2)
        ]
        try JSONEncoder().encode(SavedDemo(state: state)).write(to: file)
        let repository = DemoRepository(persistenceURL: file)

        let rolled = try await repository.bootstrap()

        #expect(rolled.voteDay == ContentRules.utcDay())
        #expect(rolled.votedDogId == nil)
        #expect(rolled.standings.allSatisfy { $0.votes == 0 })
        #expect(rolled.standings.first { $0.dogId == DemoContent.dogIds[0] }?.wins == 3)
        #expect(rolled.standings.first { $0.dogId == DemoContent.dogIds[1] }?.wins == 1)
        try await repository.markActivityRead()
        let restored = try await DemoRepository(persistenceURL: file).bootstrap()
        #expect(restored.standings == rolled.standings)
        var noVotes = restored
        noVotes.voteDay = state.voteDay
        try JSONEncoder().encode(SavedDemo(state: noVotes)).write(to: file)
        let afterEmptyDay = try await DemoRepository(persistenceURL: file).bootstrap()
        #expect(afterEmptyDay.standings == rolled.standings)
    }
    @Test func profileOwnershipAndAccountDeletion() async throws {
        let repo = DemoRepository(); let initial = try await repo.bootstrap()
        var foreign = initial.dogs[1]; foreign.name = "Nope"
        await #expect(throws: TikDogError.self) { try await repo.saveDog(foreign) }
        let dog = Dog(ownerId: DemoContent.ownerId, name: "Pepper", breed: "Rescue mix", bio: "New here!")
        let saved = try await repo.saveDog(dog); #expect(saved.id == dog.id)
        try await repo.deleteAccount(); let deleted = try await repo.bootstrap()
        #expect(deleted.userId == nil)
        #expect(!deleted.dogs.contains { $0.ownerId == DemoContent.ownerId })
        #expect(!deleted.videos.contains { $0.dogId == DemoContent.dogIds[0] })
    }
    @Test func uploadCopiesDurableMediaAndCanBeDeleted() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent("TikDogUploadTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let movie = folder.appendingPathComponent("input.mp4"), thumbnail = folder.appendingPathComponent("input.jpg")
        try Data([0, 1, 2]).write(to: movie); try Data([3, 4]).write(to: thumbnail)
        let repo = DemoRepository(persistenceURL: folder.appendingPathComponent("state.json"), mediaDirectory: folder.appendingPathComponent("media"))
        let draft = Video(dogId: DemoContent.dogIds[0], caption: "My first adventure", mediaPath: "", duration: 5)
        let published = try await repo.publish(draft, file: movie, thumbnail: thumbnail) { _ in }
        let output = URL(string: published.mediaPath)!
        #expect(try Data(contentsOf: output) == Data([0, 1, 2]))
        try await repo.deleteVideo(id: published.id)
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try await repo.profile(dogId: draft.dogId).videos.allSatisfy { $0.id != published.id })
    }
    @Test func reportsAndBlocksStayHiddenAfterRelaunch() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent("TikDogModerationTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        let repo = DemoRepository(persistenceURL: file)
        let state = try await repo.bootstrap()
        try await repo.report(videoId: state.videos[0].id, reason: "inappropriate")
        let restored = DemoRepository(persistenceURL: file)
        #expect(try await restored.bootstrap().videos.allSatisfy { $0.id != state.videos[0].id })
        #expect(try await restored.profile(dogId: state.dogs[0].id).videos.allSatisfy { $0.id != state.videos[0].id })
        try await restored.block(ownerId: DemoContent.otherOwnerId)
        let blocked = try await restored.bootstrap()
        #expect(blocked.dogs.count == 1); #expect(blocked.followingDogIds.isEmpty)
        #expect(await restored.comments(videoId: state.videos[0].id).isEmpty)
    }
    @Test func accountDeletionRemovesSocialTracesOnOtherVideos() async throws {
        let repo = DemoRepository(); let before = try await repo.bootstrap(); let foreign = before.videos[1]
        try await repo.setLike(videoId: foreign.id, liked: true)
        _ = try await repo.addComment(videoId: foreign.id, body: "A comment to delete")
        try await repo.deleteAccount()
        let after = try await repo.bootstrap()
        #expect(after.videos.first { $0.id == foreign.id }?.likeCount == foreign.likeCount)
        #expect(after.videos.first { $0.id == foreign.id }?.commentCount == foreign.commentCount)
        #expect(await repo.comments(videoId: foreign.id).allSatisfy { $0.body != "A comment to delete" })
    }
    @Test func supabaseDecodesRealTimestampAndSnakeCase() throws {
        let json = """
        {"id":"10000000-0000-4000-8000-000000000001","dog_id":"00000000-0000-4000-8000-000000000001","caption":"Hi","hashtags":[],"media_path":"https://example.com/a.mp4","thumbnail_path":"","duration":5,"like_count":0,"comment_count":0,"view_count":0,"created_at":"2026-10-18T01:00:00.123456+00:00"}
        """
        let video = try SupabaseRepository.decoder().decode(Video.self, from: Data(json.utf8))
        #expect(video.dogId == DemoContent.dogIds[0]); #expect(video.caption == "Hi")
    }
    @Test func newContributionsAreMarkedPendingAndExcludedFromDiscovery() async throws {
        let repo = DemoRepository()
        let dog = try await repo.saveDog(Dog(ownerId: DemoContent.ownerId, name: "Pepper", breed: "Mix"))
        #expect(dog.moderationStatus == .pending)
        #expect(await repo.discover(query: "Pepper").isEmpty)
        #expect(try await repo.profile(dogId: dog.id).dog.name == "Pepper")
        let video = try #require(try await repo.bootstrap().videos.first)
        let comment = try await repo.addComment(videoId: video.id, body: "Waiting for a human")
        #expect(comment.moderationStatus == .pending)
    }
    @Test func reportedCommentsAndProfilesPersistAndAccountsCanBeUnblocked() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent("TikDogSafety-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json"), repo = DemoRepository(persistenceURL: folder.appendingPathComponent("state.json"))
        let video = try #require(try await repo.bootstrap().videos.first)
        let comment = try #require(await repo.comments(videoId: video.id).first)
        try await repo.reportContent(kind: .comment, id: comment.id, reason: "inappropriate")
        try await repo.reportContent(kind: .dog, id: DemoContent.dogIds[1], reason: "inappropriate")
        let restored = DemoRepository(persistenceURL: file)
        #expect(await restored.comments(videoId: video.id).isEmpty)
        #expect(try await restored.bootstrap().dogs.allSatisfy { $0.id != DemoContent.dogIds[1] })
        try await restored.block(ownerId: DemoContent.otherOwnerId)
        #expect(await restored.blockedAccounts().count == 1)
        try await restored.unblock(ownerId: DemoContent.otherOwnerId)
        #expect(await restored.blockedAccounts().isEmpty)
    }

}
