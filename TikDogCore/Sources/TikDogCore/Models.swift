import Foundation

public enum ContentStatus: String, Codable, Sendable { case pending, ready, hidden }

public enum SubmissionVisibility: Equatable, Sendable {
    case publicVideo, profileInReview, videoInReview, bothInReview, removed
    public init(video: ContentStatus, dog: ContentStatus) {
        if video == .hidden || dog == .hidden { self = .removed }
        else if video == .pending && dog == .pending { self = .bothInReview }
        else if dog == .pending { self = .profileInReview }
        else if video == .pending { self = .videoInReview }
        else { self = .publicVideo }
    }
    public var title: String {
        switch self {
        case .publicVideo: "Public"
        case .profileInReview: "Dog profile in review"
        case .videoInReview: "Video in review"
        case .bothInReview: "Dog and video in review"
        case .removed: "Removed from public view"
        }
    }
    public var explanation: String {
        switch self {
        case .publicVideo: "Your dog's profile and this video have been approved. Everyone can see this video."
        case .profileInReview: "Your video is approved. Only you can see it until your dog's profile is approved too."
        case .videoInReview: "Your dog's profile is approved. Only you can see this video until its review is complete."
        case .bothInReview: "Only you can see this submission until your dog's profile and this video are both approved."
        case .removed: "This dog profile or video was removed from public view. Read the community guidelines before editing your profile or submitting a new video."
        }
    }
}

public struct Dog: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var ownerId: UUID
    public var name: String
    public var breed: String
    public var birthday: String
    public var bio: String
    public var avatarPath: String
    public var displayAvatarPath: String?
    public var status: ContentStatus?
    public var moderationStatus: ContentStatus { status ?? .pending }
    public var followerCount: Int
    public var followingCount: Int
    public var isFeatured: Bool

    public init(id: UUID = UUID(), ownerId: UUID, name: String, breed: String, birthday: String = "", bio: String = "", avatarPath: String = "", followerCount: Int = 0, followingCount: Int = 0, isFeatured: Bool = false) {
        self.id = id; self.ownerId = ownerId; self.name = name; self.breed = breed
        self.birthday = birthday; self.bio = bio; self.avatarPath = avatarPath; self.status = .ready
        self.followerCount = followerCount; self.followingCount = followingCount; self.isFeatured = isFeatured
    }
}

public struct Video: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var dogId: UUID
    public var caption: String
    public var hashtags: [String]
    public var mediaPath: String
    public var thumbnailPath: String
    public var playbackPath: String?
    public var displayThumbnailPath: String?
    public var status: ContentStatus?
    public var moderationStatus: ContentStatus { status ?? .pending }
    public var duration: Double
    public var likeCount: Int
    public var commentCount: Int
    public var viewCount: Int
    public var createdAt: Date

    public init(id: UUID = UUID(), dogId: UUID, caption: String, hashtags: [String] = [], mediaPath: String, thumbnailPath: String = "", duration: Double = 10, likeCount: Int = 0, commentCount: Int = 0, viewCount: Int = 0, createdAt: Date = .now) {
        self.id = id; self.dogId = dogId; self.caption = caption; self.hashtags = hashtags
        self.mediaPath = mediaPath; self.status = .ready; self.thumbnailPath = thumbnailPath; self.duration = duration
        self.likeCount = likeCount; self.commentCount = commentCount; self.viewCount = viewCount; self.createdAt = createdAt
    }
}

public struct DogComment: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var videoId: UUID
    public var userId: UUID
    public var author: String
    public var body: String
    public var status: ContentStatus?
    public var moderationStatus: ContentStatus { status ?? .pending }
    public var createdAt: Date

    public init(id: UUID = UUID(), videoId: UUID, userId: UUID, author: String, body: String, createdAt: Date = .now) {
        self.id = id; self.videoId = videoId; self.userId = userId; self.author = author; self.status = .ready; self.body = body; self.createdAt = createdAt
    }
}

public struct ActivityItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: String
    public var dogId: UUID?
    public var videoId: UUID?
    public var message: String
    public var createdAt: Date
    public var isRead: Bool

    public init(id: UUID = UUID(), kind: String, dogId: UUID? = nil, videoId: UUID? = nil, message: String, createdAt: Date = .now, isRead: Bool = false) {
        self.id = id; self.kind = kind; self.dogId = dogId; self.videoId = videoId
        self.message = message; self.createdAt = createdAt; self.isRead = isRead
    }
}

public struct DailyStanding: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID { dogId }
    public var dogId: UUID
    public var votes: Int
    public var wins: Int
    public init(dogId: UUID, votes: Int, wins: Int = 0) { self.dogId = dogId; self.votes = votes; self.wins = wins }
}

public enum FeedKind: String, CaseIterable, Codable, Sendable { case forYou = "for_you", following }

public struct FeedPage: Codable, Sendable {
    public var videos: [Video]
    public var dogs: [Dog]
    public var nextOffset: Int?
    public init(videos: [Video], dogs: [Dog], nextOffset: Int? = nil) {
        self.videos = videos; self.dogs = dogs; self.nextOffset = nextOffset
    }
}

public struct AppSnapshot: Codable, Sendable {
    public var dogs: [Dog]
    public var videos: [Video]
    public var likedVideoIds: Set<UUID>
    public var bookmarkedVideoIds: Set<UUID>
    public var followingDogIds: Set<UUID>
    public var blockedOwnerIds: Set<UUID>
    public var activities: [ActivityItem]
    public var standings: [DailyStanding]
    public var votedDogId: UUID?
    public var voteDay: String
    public var userId: UUID?
    public var displayName: String

    public init(dogs: [Dog] = [], videos: [Video] = [], likedVideoIds: Set<UUID> = [], bookmarkedVideoIds: Set<UUID> = [], followingDogIds: Set<UUID> = [], blockedOwnerIds: Set<UUID> = [], activities: [ActivityItem] = [], standings: [DailyStanding] = [], votedDogId: UUID? = nil, voteDay: String = "", userId: UUID? = nil, displayName: String = "Dog person") {
        self.dogs = dogs; self.videos = videos; self.likedVideoIds = likedVideoIds
        self.bookmarkedVideoIds = bookmarkedVideoIds; self.followingDogIds = followingDogIds; self.blockedOwnerIds = blockedOwnerIds
        self.activities = activities; self.standings = standings; self.votedDogId = votedDogId; self.voteDay = voteDay
        self.userId = userId; self.displayName = displayName
    }
    public mutating func merge(dogs incomingDogs: [Dog] = [], videos incomingVideos: [Video] = []) {
        for dog in incomingDogs {
            if let index = dogs.firstIndex(where: { $0.id == dog.id }) { dogs[index] = dog } else { dogs.append(dog) }
        }
        for video in incomingVideos {
            if let index = videos.firstIndex(where: { $0.id == video.id }) { videos[index] = video } else { videos.append(video) }
        }
    }
}

public struct AuthSession: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Double?
    public var user: AuthUser
    public init(accessToken: String, refreshToken: String, expiresAt: Double? = nil, user: AuthUser) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt; self.user = user
    }
    private enum CodingKeys: String, CodingKey { case accessToken, refreshToken, expiresAt, expiresIn, user }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try values.decode(String.self, forKey: .accessToken)
        refreshToken = try values.decode(String.self, forKey: .refreshToken)
        user = try values.decode(AuthUser.self, forKey: .user)
        let absolute = try values.decodeIfPresent(Double.self, forKey: .expiresAt)
        let lifetime = try values.decodeIfPresent(Double.self, forKey: .expiresIn) ?? 3600
        expiresAt = absolute ?? (Date.now.timeIntervalSince1970 + lifetime)
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(accessToken, forKey: .accessToken); try values.encode(refreshToken, forKey: .refreshToken)
        try values.encodeIfPresent(expiresAt, forKey: .expiresAt); try values.encode(user, forKey: .user)
    }
}
public struct AuthUser: Codable, Sendable {
    public var id: UUID
    public var email: String?
    public init(id: UUID, email: String? = nil) { self.id = id; self.email = email }
}

public struct ProfilePage: Codable, Sendable {
    public var dog: Dog
    public var videos: [Video]
    public init(dog: Dog, videos: [Video]) { self.dog = dog; self.videos = videos }
}

public enum TikDogError: LocalizedError, Equatable, Sendable {
    case signInRequired, invalidInput(String), server(String), alreadyVoted, unavailable
    public var errorDescription: String? {
        switch self {
        case .signInRequired: "Sign in to join the pack."
        case .invalidInput(let message), .server(let message): message
        case .alreadyVoted: "You've already picked your dog for today. Come back tomorrow!"
        case .unavailable: "This isn't available right now. Please try again."
        }
    }
}

public enum ContentRules {
    public static func hashtags(from text: String) -> [String] {
        var seen = Set<String>()
        return text.split { $0.isWhitespace || $0 == "," }.compactMap { part in
            let clean = part.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
            guard !clean.isEmpty, seen.insert(clean).inserted else { return nil }
            return String(clean.prefix(40))
        }.prefix(8).map { $0 }
    }
    public static func validateDog(name: String, breed: String, bio: String) throws {
        guard (1...30).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count) else { throw TikDogError.invalidInput("Give your dog a name (up to 30 characters).") }
        guard (1...60).contains(breed.trimmingCharacters(in: .whitespacesAndNewlines).count), bio.count <= 160 else { throw TikDogError.invalidInput("Add a breed and keep the bio under 160 characters.") }
    }
    public static func validateVideo(caption: String, duration: Double) throws {
        guard caption.count <= 300 else { throw TikDogError.invalidInput("Keep the caption under 300 characters.") }
        guard duration.isFinite, duration >= 1, duration <= 60.1 else { throw TikDogError.invalidInput("Choose a clip between 1 and 60 seconds.") }
    }
    public static func utcDay(_ date: Date = .now) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
}

public enum FeedRanking {
    /// The discovery boost deliberately gives less-followed dogs a chance to surface.
    public static func score(_ video: Video, followers: Int, now: Date = .now) -> Double {
        let ageHours = max(0, now.timeIntervalSince(video.createdAt) / 3600)
        let engagement = Double(video.likeCount) + Double(video.commentCount) * 3 + Double(video.viewCount) * 0.03
        let discovery = followers < 1000 ? 1.4 : 1.0
        return (log1p(engagement) + 1) * discovery / pow(ageHours + 2, 0.8)
    }
}

public struct AccountState: Codable, Sendable {
    public var termsVersion: String?
    public var isSuspended: Bool
    public var isDeleting: Bool
    public init(termsVersion: String? = nil, isSuspended: Bool = false, isDeleting: Bool = false) {
        self.termsVersion = termsVersion; self.isSuspended = isSuspended; self.isDeleting = isDeleting
    }
}
public struct BlockedAccount: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public init(id: UUID, name: String) { self.id = id; self.name = name }
}
public enum ReportTarget: String, Sendable { case video, comment, dog }
public enum CommunityTerms { public static let version = "2026-10-18" }

public protocol TikDogRepository: Sendable {
    var isDemo: Bool { get }
    func accountState() async throws -> AccountState
    func acceptTerms() async throws
    func reportContent(kind: ReportTarget, id: UUID, reason: String) async throws
    func blockedAccounts() async throws -> [BlockedAccount]
    func unblock(ownerId: UUID) async throws
    func bootstrap() async throws -> AppSnapshot
    func feed(kind: FeedKind, offset: Int, limit: Int) async throws -> FeedPage
    func discover(query: String) async throws -> [Dog]
    func profile(dogId: UUID) async throws -> ProfilePage
    func setLike(videoId: UUID, liked: Bool) async throws
    func setBookmark(videoId: UUID, saved: Bool) async throws
    func setFollow(dogId: UUID, following: Bool) async throws
    func comments(videoId: UUID) async throws -> [DogComment]
    func addComment(videoId: UUID, body: String) async throws -> DogComment
    func saveDog(_ dog: Dog) async throws -> Dog
    func uploadAvatar(file: URL) async throws -> String
    func publish(_ video: Video, file: URL, thumbnail: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> Video
    func vote(dogId: UUID) async throws -> [DailyStanding]
    func report(videoId: UUID, reason: String) async throws
    func block(ownerId: UUID) async throws
    func markActivityRead() async throws
    func deleteVideo(id: UUID) async throws
    func deleteAccount() async throws
}
