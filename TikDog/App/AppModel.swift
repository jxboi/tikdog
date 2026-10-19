import SwiftUI
import TikDogCore

struct FeedFailure {
    enum Recovery { case refresh, page(reset: Bool) }
    let message: String
    let recovery: Recovery
}

@MainActor @Observable final class AppModel {
    private(set) var repository: any TikDogRepository
    private(set) var snapshot = AppSnapshot()
    private(set) var stateRevision = UUID()
    var feedKind: FeedKind = .forYou
    var feedIds: [FeedKind: [UUID]] = [:]
    var nextOffsets: [FeedKind: Int] = [:]
    var exhausted: Set<FeedKind> = []
    var loadingFeeds: Set<FeedKind> = []
    private(set) var feedFailures: [FeedKind: FeedFailure] = [:]
    private var feedRequests: [FeedKind: UUID] = [:]
    private(set) var dataEpoch = UUID()
    private(set) var sessionEpoch = UUID()
    var isLoading = true
    var configurationError: String?
    var accountState = AccountState()
    var showTerms = false
    var errorMessage: String?
    var toast: String?
    var showAuth = false
    var isUploadPresented = false
    var focusVideoId: UUID?
    var selectedDog: Dog?
    var selectedOwnDogId: UUID?
    var selectedVideo: Video?
    var pendingActions: Set<String> = []
    var selectedTab: AppTab = .home
    private var toastTask: Task<Void, Never>?

    var isDemo: Bool { repository.isDemo }
    var ownDogs: [Dog] { snapshot.dogs.filter { $0.ownerId == snapshot.userId } }
    var selectedOwnDog: Dog? { ownDogs.first { $0.id == selectedOwnDogId } ?? ownDogs.first }
    var visibleDogs: [Dog] { snapshot.dogs.filter { $0.moderationStatus == .ready && !snapshot.blockedOwnerIds.contains($0.ownerId) } }
    var homeVideos: [Video] {
        let dogIds = Set(visibleDogs.map(\.id))
        return (feedIds[feedKind] ?? []).compactMap { id in snapshot.videos.first { $0.id == id } }
            .filter { $0.moderationStatus == .ready && dogIds.contains($0.dogId) }
    }
    var visibleVideos: [Video] { let dogIds = Set(visibleDogs.map(\.id)); return snapshot.videos.filter { $0.moderationStatus == .ready && dogIds.contains($0.dogId) } }
    var savedVideos: [Video] { visibleVideos.filter { snapshot.bookmarkedVideoIds.contains($0.id) } }
    var unreadCount: Int { snapshot.activities.filter { !$0.isRead }.count }

    init(repository: any TikDogRepository) { self.repository = repository }
    static func configured() -> AppModel {
        #if DEBUG
        let useDemo = ProcessInfo.processInfo.arguments.contains("--demo")
        #else
        let useDemo = false
        #endif
        if !useDemo,
           let urlText = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
           let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
           !urlText.isEmpty, !urlText.contains("$("), !key.isEmpty, !key.contains("$("), SupabaseConfiguration.isPublishableKey(key), let url = URL(string: urlText), url.scheme == "https" {
            return AppModel(repository: SupabaseRepository(configuration: .init(url: url, publishableKey: key), sessionStorage: KeychainSessionStorage()))
        }
        #if !DEBUG
        let unavailable = AppModel(repository: DemoRepository())
        unavailable.configurationError = "TikDog is temporarily unavailable. Please try again later."
        return unavailable
        #else
        let base = URL.documentsDirectory.appendingPathComponent("TikDog", isDirectory: true)
        if ProcessInfo.processInfo.arguments.contains("--reset-demo") { try? FileManager.default.removeItem(at: base) }
        return AppModel(repository: DemoRepository(persistenceURL: base.appendingPathComponent("demo.json"), mediaDirectory: base.appendingPathComponent("Media")))
        #endif
    }
    func load(retryIfChanged: Bool = true) async {
        guard configurationError == nil else { isLoading = false; return }
        let epoch = UUID(); dataEpoch = epoch; feedRequests = [:]; loadingFeeds = []; feedFailures = [:]
        let revision = stateRevision
        isLoading = true
        defer { if dataEpoch == epoch { isLoading = false } }
        do {
            let state = try await repository.accountState()
            var latest = try await repository.bootstrap()
            let kind = feedKind
            let page = try await repository.feed(kind: kind, offset: 0, limit: 8)
            for dog in page.dogs {
                latest.dogs.removeAll { $0.id == dog.id }; latest.dogs.append(dog)
            }
            for video in page.videos {
                latest.videos.removeAll { $0.id == video.id }; latest.videos.append(video)
            }
            let viewedIds = Set([selectedDog?.id, selectedVideo?.dogId].compactMap { $0 })
            for id in viewedIds where !latest.dogs.contains(where: { $0.id == id && $0.ownerId == latest.userId }) {
                do {
                    let page = try await repository.profile(dogId: id)
                    latest.dogs.removeAll { $0.id == id }; latest.dogs.append(page.dog)
                    latest.videos.removeAll { $0.dogId == id }; latest.videos.append(contentsOf: page.videos)
                } catch {
                    guard dataEpoch == epoch else { return }
                    if selectedDog?.id == id { selectedDog = nil }
                    if selectedVideo?.dogId == id { selectedVideo = nil }
                }
            }
            guard dataEpoch == epoch else { return }
            guard revision == stateRevision else {
                if retryIfChanged { await load(retryIfChanged: false) }
                return
            }
            if snapshot.userId != latest.userId { sessionEpoch = UUID(); selectedOwnDogId = nil }
            snapshot = latest; accountState = state; stateRevision = UUID()
            feedRequests = [:]; loadingFeeds = []; feedFailures = [:]
            showTerms = snapshot.userId != nil && state.termsVersion != CommunityTerms.version && !state.isSuspended && !state.isDeleting
            feedIds = [kind: page.videos.map(\.id)]
            nextOffsets = page.nextOffset.map { [kind: $0] } ?? [:]
            exhausted = page.nextOffset == nil ? [kind] : []
            if kind != feedKind { await loadFeed(reset: true) }
        } catch { if dataEpoch == epoch { handleFeedFailure(error, kind: feedKind, recovery: .refresh) } }
    }
    func loadFeed(reset: Bool = false, kind requested: FeedKind? = nil) async {
        let kind = requested ?? feedKind
        guard !loadingFeeds.contains(kind), reset || !exhausted.contains(kind) else { return }
        feedFailures[kind] = nil
        let epoch = dataEpoch, request = UUID(); feedRequests[kind] = request
        loadingFeeds.insert(kind)
        defer { if feedRequests[kind] == request { loadingFeeds.remove(kind); feedRequests[kind] = nil } }
        do {
            while !Task.isCancelled {
                let revision = stateRevision
                let page = try await repository.feed(kind: kind, offset: reset ? 0 : (nextOffsets[kind] ?? 0), limit: 8)
                guard !Task.isCancelled && epoch == dataEpoch && feedRequests[kind] == request else { return }
                guard revision == stateRevision else { continue }
                merge(dogs: page.dogs, videos: page.videos)
                var ids = reset ? [] : (feedIds[kind] ?? [])
                for video in page.videos where !ids.contains(video.id) { ids.append(video.id) }
                feedIds[kind] = ids
                if let offset = page.nextOffset { nextOffsets[kind] = offset; exhausted.remove(kind) } else { exhausted.insert(kind) }
                return
            }
        } catch {
            if dataEpoch == epoch && feedRequests[kind] == request { handleFeedFailure(error, kind: kind, recovery: .page(reset: reset)) }
        }
    }
    func retryFeed(kind: FeedKind? = nil) async {
        let kind = kind ?? feedKind
        guard let failure = feedFailures[kind] else { return }
        switch failure.recovery {
        case .refresh: await load()
        case .page(let reset): await loadFeed(reset: reset, kind: kind)
        }
    }
    private func handleFeedFailure(_ error: Error, kind: FeedKind, recovery: FeedFailure.Recovery) {
        guard !Task.isCancelled && !(error is CancellationError) && (error as? URLError)?.code != .cancelled else { return }
        feedFailures[kind] = FeedFailure(message: error.localizedDescription, recovery: recovery)
        if case .refresh = recovery { handle(error) }
        else if error as? TikDogError == .signInRequired { handle(error) }
    }
    func merge(dogs: [Dog] = [], videos: [Video] = []) {
        snapshot.merge(dogs: dogs, videos: videos)
    }
    func applyLocalChange(_ update: (inout AppSnapshot) -> Void) {
        stateRevision = UUID()
        update(&snapshot)
    }
    func mergeLocal(dogs: [Dog] = [], videos: [Video] = []) {
        applyLocalChange { $0.merge(dogs: dogs, videos: videos) }
    }
    func dog(for video: Video) -> Dog? { snapshot.dogs.first { $0.id == video.dogId } }
    @discardableResult func requireMember() -> Bool {
        guard snapshot.userId != nil else { showAuth = true; return false }
        guard !accountState.isSuspended && !accountState.isDeleting else { errorMessage = accountState.isDeleting ? "Account deletion has started. Open Settings to retry deletion." : "Your account is suspended. You can contact support or delete your account in Settings."; return false }
        guard accountState.termsVersion == CommunityTerms.version else { showTerms = true; return false }
        return true
    }
    func presentUpload() { if requireMember() { isUploadPresented = true } }
    func signOut() async throws {
        clearAccountData()
        if let backend = repository as? SupabaseRepository { try await backend.signOut() }
        await load()
    }
    private func clearAccountData() {
        sessionEpoch = UUID(); toastTask?.cancel(); toast = nil; showTerms = false; isUploadPresented = false
        dataEpoch = UUID(); feedRequests = [:]; loadingFeeds = []
        snapshot = AppSnapshot(); stateRevision = UUID(); accountState = AccountState(); feedIds = [:]; feedFailures = [:]; selectedDog = nil; selectedOwnDogId = nil; selectedVideo = nil
        nextOffsets = [:]; exhausted = []; focusVideoId = nil; showAuth = false; errorMessage = nil
    }
    func deleteAccount() async throws {
        let session = sessionEpoch
        try await repository.deleteAccount()
        guard session == sessionEpoch else { return }
        clearAccountData()
        await load()
    }
    func replaceProfile(_ page: ProfilePage) {
        snapshot.videos.removeAll { $0.dogId == page.dog.id }
        merge(dogs: [page.dog], videos: page.videos)
    }
    func blockOwner(_ ownerId: UUID) async throws {
        let epoch = sessionEpoch
        try await repository.block(ownerId: ownerId)
        guard epoch == sessionEpoch else { return }
        let dogIds = snapshot.dogs.filter { $0.ownerId == ownerId }.map(\.id)
        applyLocalChange { state in
            state.blockedOwnerIds.insert(ownerId)
            state.followingDogIds.subtract(dogIds)
            state.activities = []
        }
        selectedDog = nil; selectedVideo = nil
        notify("Account blocked")
    }
    func handle(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        if let error = error as? TikDogError, error == .signInRequired { showAuth = true }
        else { errorMessage = error.localizedDescription }
    }
    func notify(_ message: String) {
        toastTask?.cancel(); toast = message
        toastTask = Task { try? await Task.sleep(for: .seconds(3)); if !Task.isCancelled { toast = nil } }
    }
    func like(_ video: Video, force: Bool = false) async {
        guard requireMember() else { return }
        let key = "like-\(video.id)"; guard pendingActions.insert(key).inserted else { return }; defer { pendingActions.remove(key) }
        let wasLiked = snapshot.likedVideoIds.contains(video.id); let liked = force || !wasLiked
        guard liked != wasLiked else { return }
        let epoch = sessionEpoch
        setLocalLike(video.id, liked: liked); Haptics.like()
        do {
            try await repository.setLike(videoId: video.id, liked: liked)
            if epoch == sessionEpoch { setLocalLike(video.id, liked: liked) }
        }
        catch { if epoch == sessionEpoch { setLocalLike(video.id, liked: wasLiked); handle(error) } }
    }
    private func setLocalLike(_ id: UUID, liked: Bool) {
        applyLocalChange { state in
            let changed = liked != state.likedVideoIds.contains(id)
            if liked { state.likedVideoIds.insert(id) } else { state.likedVideoIds.remove(id) }
            if changed, let i = state.videos.firstIndex(where: { $0.id == id }) { state.videos[i].likeCount = max(0, state.videos[i].likeCount + (liked ? 1 : -1)) }
        }
    }
    func bookmark(_ video: Video) async {
        guard requireMember() else { return }
        let key = "bookmark-\(video.id)"; guard pendingActions.insert(key).inserted else { return }; defer { pendingActions.remove(key) }
        let saved = !snapshot.bookmarkedVideoIds.contains(video.id)
        let epoch = sessionEpoch
        do {
            try await repository.setBookmark(videoId: video.id, saved: saved)
            guard epoch == sessionEpoch else { return }
            applyLocalChange { state in
                if saved { state.bookmarkedVideoIds.insert(video.id) } else { state.bookmarkedVideoIds.remove(video.id) }
            }
            Haptics.selection(); notify(saved ? "Saved to your collection" : "Removed from saved")
        } catch { if epoch == sessionEpoch { handle(error) } }
    }
    func follow(_ dog: Dog) async {
        guard requireMember(), dog.ownerId != snapshot.userId else { return }
        let key = "follow-\(dog.id)"; guard pendingActions.insert(key).inserted else { return }; defer { pendingActions.remove(key) }
        let followed = !snapshot.followingDogIds.contains(dog.id)
        let epoch = sessionEpoch
        do {
            try await repository.setFollow(dogId: dog.id, following: followed)
            guard epoch == sessionEpoch else { return }
            applyLocalChange { state in
                let changed = followed != state.followingDogIds.contains(dog.id)
                if followed { state.followingDogIds.insert(dog.id) } else { state.followingDogIds.remove(dog.id) }
                if changed, let i = state.dogs.firstIndex(where: { $0.id == dog.id }) { state.dogs[i].followerCount = max(0, state.dogs[i].followerCount + (followed ? 1 : -1)) }
            }
            exhausted.remove(.following); feedIds[.following] = nil
            feedRequests[.following] = nil; loadingFeeds.remove(.following)
            Haptics.selection()
            if feedKind == .following { await loadFeed(reset: true, kind: .following) }
        } catch { if epoch == sessionEpoch { handle(error) } }
    }
    func vote(_ dog: Dog) async {
        guard requireMember(), pendingActions.insert("vote").inserted else { return }; defer { pendingActions.remove("vote") }
        let epoch = sessionEpoch
        do {
            let standings = try await repository.vote(dogId: dog.id)
            guard epoch == sessionEpoch else { return }
            applyLocalChange { state in state.standings = standings; state.votedDogId = dog.id; state.voteDay = ContentRules.utcDay() }
            Haptics.like(); notify("A vote for \(dog.name). A very good choice.")
        } catch { if epoch == sessionEpoch { handle(error) } }
    }
    func report(_ video: Video, reason: String) async {
        guard requireMember() else { return }
        let epoch = sessionEpoch
        do {
            try await repository.report(videoId: video.id, reason: reason)
            guard epoch == sessionEpoch else { return }
            applyLocalChange { $0.videos.removeAll { $0.id == video.id } }; notify("Report received. This video is hidden.")
        } catch { if epoch == sessionEpoch { handle(error) } }
    }
    func block(_ dog: Dog) async {
        guard requireMember() else { return }
        let epoch = sessionEpoch
        do { try await blockOwner(dog.ownerId) }
        catch { if epoch == sessionEpoch { handle(error) } }
    }
    func refreshActivity() async {
        guard snapshot.userId != nil else { return }
        let epoch = dataEpoch, revision = stateRevision
        do {
            let latest = try await repository.bootstrap()
            guard epoch == dataEpoch && revision == stateRevision else { return }
            snapshot.activities = latest.activities
            merge(dogs: latest.dogs)
        } catch { if epoch == dataEpoch { handle(error) } }
    }
    func refreshVoting() async {
        let epoch = dataEpoch, revision = stateRevision
        do {
            let latest = try await repository.bootstrap()
            guard epoch == dataEpoch && revision == stateRevision else { return }
            snapshot.standings = latest.standings; snapshot.votedDogId = latest.votedDogId; snapshot.voteDay = latest.voteDay
            merge(dogs: latest.dogs)
        } catch { if epoch == dataEpoch { handle(error) } }
    }
    func markRead() async {
        guard snapshot.userId != nil else { return }
        let epoch = sessionEpoch
        do {
            try await repository.markActivityRead()
            guard epoch == sessionEpoch else { return }
            applyLocalChange { state in for i in state.activities.indices { state.activities[i].isRead = true } }
        } catch { if epoch == sessionEpoch { handle(error) } }
    }
    func deleteVideo(_ video: Video) async {
        let epoch = sessionEpoch
        do {
            try await repository.deleteVideo(id: video.id)
            guard epoch == sessionEpoch else { return }
            applyLocalChange { $0.videos.removeAll { $0.id == video.id } }; selectedVideo = nil; notify("Video deleted")
        } catch { if epoch == sessionEpoch { handle(error) } }
    }
}

enum AppTab: String, CaseIterable { case home = "Home", discover = "Discover", upload = "Upload", activity = "Activity", profile = "Profile"
    var icon: String { switch self { case .home: "house.fill"; case .discover: "safari"; case .upload: "plus"; case .activity: "bell"; case .profile: "person.crop.circle" } }
}
