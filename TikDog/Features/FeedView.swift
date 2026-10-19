import SwiftUI
import TikDogCore

struct FeedView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var playback = PlaybackController()
    @State private var currentId: UUID?
    @State private var commentsVideo: Video?
    @State private var showReport: Video?
    @State private var localAuth = false
    var standaloneVideos: [Video]? = nil
    var initialVideo: UUID? = nil
    var isStandalone = false
    @Environment(\.dismiss) private var dismiss
    private var videos: [Video] { standaloneVideos?.compactMap { item in app.snapshot.videos.first { $0.id == item.id } } ?? app.homeVideos }
    private var activeVideo: Video? { videos.first { $0.id == currentId } ?? videos.first }

    private var isCovered: Bool { commentsVideo != nil || showReport != nil || localAuth || app.showAuth || app.showTerms || app.errorMessage != nil || (!isStandalone && (app.selectedDog != nil || app.isUploadPresented)) }
    private func requireMember() -> Bool { if app.snapshot.userId == nil { localAuth = true; return false }; return true }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.black
                if videos.isEmpty {
                    VStack(spacing: 12) {
                        if isStandalone {
                            EmptyState(icon: "video.slash", title: "This adventure is unavailable", message: "It may have been removed or is no longer shared with you.")
                            Button("Go back") { dismiss() }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 60)
                        }
                        else if app.isLoading || app.loadingFeeds.contains(app.feedKind) { ProgressView().tint(.dogOrange); Text("Finding your next favorite dog…").font(.subheadline).foregroundStyle(.white.opacity(0.6)) }
                        else if let failure = app.feedFailures[app.feedKind] {
                            EmptyState(icon: "wifi.exclamationmark", title: "Adventures couldn't load", message: "Check your connection and try again.")
                            Button("Try again") { Task { await app.retryFeed() } }
                                .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 44).accessibilityHint(failure.message)
                        }
                        else {
                            EmptyState(icon: "pawprint", title: app.feedKind == .following ? "Your pack starts here" : "The first of many adventures", message: app.feedKind == .following ? "Follow a few dogs and their latest adventures will show up here." : "Every pack starts with one adventure. Share a little of your dog's world.")
                            Button(app.feedKind == .following ? "Find your pack" : "Share an adventure") {
                                if app.feedKind == .following { app.selectedTab = .discover } else { app.presentUpload() }
                            }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 44).accessibilityIdentifier("emptyFeedAction")
                            Button("Refresh feed") { Task { await app.loadFeed(reset: true) } }.font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.75)).frame(minHeight: 44).accessibilityIdentifier("refreshEmptyFeed")
                        }
                    }.foregroundStyle(.white).frame(maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(videos) { video in
                                FeedCell(video: video, playback: playback, active: video.id == activeVideo?.id, onComments: { commentsVideo = video }, onReport: { showReport = video }, onRetry: { playback.retry(video, in: videos) }, requireMember: requireMember)
                                    .frame(width: geometry.size.width, height: geometry.size.height + geometry.safeAreaInsets.top).clipped().id(video.id)
                            }
                        }.scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging).scrollPosition(id: $currentId).scrollIndicators(.hidden)
                    .accessibilityIdentifier("videoFeed").accessibilityValue(activeVideo.flatMap { app.dog(for: $0)?.name } ?? "")
                }
                if isStandalone {
                    HStack { Button { dismiss() } label: { Image(systemName: "chevron.left").font(.title3.bold()).padding(14).background(.black.opacity(0.3), in: Circle()) }.accessibilityLabel("Close video"); Spacer() }.padding(.horizontal, 16).padding(.top, geometry.safeAreaInsets.top + 8)
                } else { feedHeader(top: geometry.safeAreaInsets.top) }
                if !isStandalone, !videos.isEmpty, let failure = app.feedFailures[app.feedKind] {
                    VStack {
                        Button { Task { await app.retryFeed() } } label: {
                            Label("Couldn't load adventures · Try again", systemImage: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.dogInk)
                                .padding(.horizontal, 16).frame(minHeight: 44).background(Color.dogCream, in: Capsule())
                        }.accessibilityHint(failure.message)
                        Spacer()
                    }.padding(.horizontal, 20).padding(.top, geometry.safeAreaInsets.top + 76)
                }
            }
            .foregroundStyle(.white)
            .frame(width: geometry.size.width, height: geometry.size.height + geometry.safeAreaInsets.top)
            .offset(y: -geometry.safeAreaInsets.top)
            .onAppear { currentId = app.focusVideoId ?? currentId ?? initialVideo ?? videos.first?.id; if !isStandalone { app.focusVideoId = nil }; activate() }
            .onChange(of: currentId) { _, _ in
                activate()
                loadMoreIfNeeded()
            }
            .onChange(of: videos) { _, updated in
                let ids = updated.map(\.id)
                if currentId == nil || !ids.contains(currentId!) { currentId = ids.first }; activate(); loadMoreIfNeeded()
            }
            .onChange(of: app.isLoading) { _, loading in if !loading { loadMoreIfNeeded() } }
            .onChange(of: app.loadingFeeds.contains(app.feedKind)) { _, loading in if !loading { loadMoreIfNeeded() } }
            .onChange(of: app.focusVideoId) { _, id in if !isStandalone, let id, videos.contains(where: { $0.id == id }) { currentId = id; app.focusVideoId = nil } }
            .onChange(of: app.feedKind) { _, _ in currentId = nil; playback.stop(); Task { await app.loadFeed(reset: app.feedIds[app.feedKind] == nil); currentId = videos.first?.id; activate() } }
            .onChange(of: scenePhase) { _, phase in if phase == .active && !isCovered { playback.resume(); loadMoreIfNeeded() } else { playback.suspend() } }
            .onChange(of: isCovered) { _, presented in if presented || scenePhase != .active { playback.suspend() } else { playback.resume(); loadMoreIfNeeded() } }
            .onDisappear { playback.stop() }
        }
        .sheet(isPresented: $localAuth) { AuthView().preferredColorScheme(.light) }
        .sheet(item: $commentsVideo) { video in CommentsView(video: video).presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]).presentationDragIndicator(.visible) }
        .confirmationDialog("Help keep TikDog kind", isPresented: Binding(get: { showReport != nil }, set: { if !$0 { showReport = nil } }), titleVisibility: .visible) {
            if let video = showReport {
                if let dog = app.dog(for: video), dog.ownerId == app.snapshot.userId { Button("Delete video", role: .destructive) { Task { await app.deleteVideo(video) } } }
                else {
                    Button("Report: animal harm") { if requireMember() { Task { await app.report(video, reason: "animal_harm") } } }
                    Button("Report: spam or inappropriate") { if requireMember() { Task { await app.report(video, reason: "inappropriate") } } }
                    if let dog = app.dog(for: video) { Button("Block this account", role: .destructive) { if requireMember() { Task { await app.block(dog) } } } }
                }
                Button("Cancel", role: .cancel) { showReport = nil }
            }
        }
    }
    private func activate() { playback.activate(activeVideo, in: videos); if isCovered || scenePhase != .active { playback.suspend() } }
    private func loadMoreIfNeeded() {
        guard !isStandalone && !isCovered && scenePhase == .active && !app.isLoading,
              app.feedFailures[app.feedKind] == nil,
              let activeVideo, let index = videos.firstIndex(of: activeVideo), index >= videos.count - 3 else { return }
        Task { await app.loadFeed() }
    }
    private func feedHeader(top: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) { Image(systemName: "pawprint.fill").font(.system(size: 16)); Text("tikdog").font(.system(size: 21, weight: .heavy, design: .rounded)).tracking(-1) }.foregroundStyle(.white)
            Spacer(minLength: 16)
            HStack(spacing: 22) {
                feedTab("Following", kind: .following)
                feedTab("For You", kind: .forYou)
            }
            Spacer(minLength: 16)
            Button { app.selectedTab = .discover } label: { Image(systemName: "magnifyingglass").font(.system(size: 22, weight: .medium)).frame(width: 44, height: 44) }.accessibilityLabel("Search dogs")
        }.padding(.horizontal, 20).padding(.top, top + 8).padding(.bottom, 24)
            .background(LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
    }
    private func feedTab(_ title: String, kind: FeedKind) -> some View {
        Button { Haptics.selection(); app.feedKind = kind } label: {
            VStack(spacing: 8) { Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(app.feedKind == kind ? .white : .white.opacity(0.55)); Capsule().fill(app.feedKind == kind ? Color.dogOrange : .clear).frame(width: 23, height: 3) }.padding(.top, 12)
        }.accessibilityIdentifier("feed-\(kind.rawValue)").accessibilityAddTraits(app.feedKind == kind ? .isSelected : [])
    }
}

private struct FeedCell: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let video: Video
    let playback: PlaybackController
    let active: Bool
    let onComments: () -> Void
    let onReport: () -> Void
    let onRetry: () -> Void
    let requireMember: () -> Bool
    @State private var heart = false
    private var liked: Bool { app.snapshot.likedVideoIds.contains(video.id) }
    private var saved: Bool { app.snapshot.bookmarkedVideoIds.contains(video.id) }
    private var dog: Dog? { app.dog(for: video) }
    var body: some View {
        GeometryReader { geometry in
        ZStack {
            MediaImage(path: video.displayThumbnailPath ?? video.thumbnailPath).frame(width: geometry.size.width, height: geometry.size.height).clipped()
            if let player = playback.player(for: video.id) { PlayerView(player: player).allowsHitTesting(false) }
            LinearGradient(stops: [.init(color: .clear, location: 0.4), .init(color: .black.opacity(0.2), location: 0.58), .init(color: .black.opacity(0.78), location: 1)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
            if active && playback.isPaused { Image(systemName: "play.fill").font(.system(size: 48)).foregroundStyle(.white.opacity(0.8)).shadow(radius: 15).allowsHitTesting(false).accessibilityIdentifier("pausedIndicator") }
            if active && playback.isBuffering && !playback.isPaused { ProgressView().tint(.white).scaleEffect(1.4).allowsHitTesting(false) }
            Color.clear.contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    guard requireMember() else { return }
                    Task { await app.like(video, force: true) }
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.5)) { heart = true }
                    Task { try? await Task.sleep(for: .milliseconds(750)); withAnimation(.easeOut(duration: 0.25)) { heart = false } }
                }
                .onTapGesture { if playback.activeId == video.id { playback.togglePause() } }
                .accessibilityLabel("\(dog?.name ?? "Dog") video")
                .accessibilityHint(playback.isPaused ? "Double tap to play" : "Double tap to pause")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { if active { playback.togglePause() } }
                .accessibilityAction(named: Text(liked ? "Unlike video" : "Like video")) { if requireMember() { Task { await app.like(video) } } }
                .accessibilityAction(named: Text("Open comments")) { onComments() }
                .accessibilityIdentifier("videoSurface")
                .accessibilityValue(active ? (playback.isPaused ? "Paused" : "Playing") : "Inactive")
            if active, let error = playback.playbackError {
                VStack(spacing: 12) { Text("A little playback hiccup").font(.headline); Text(error).font(.caption).lineLimit(3).multilineTextAlignment(.center); Button("Try again", action: onRetry).font(.subheadline.bold()).padding(12).background(Color.dogOrange, in: Capsule()).foregroundStyle(.black) }.padding(25).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 22)).padding(40)
            }
            if heart { Image(systemName: "heart.fill").font(.system(size: 115)).foregroundStyle(Color.dogOrange).rotationEffect(.degrees(-15)).scaleEffect(heart ? 1 : 0.2).shadow(color: .black.opacity(0.2), radius: 20).allowsHitTesting(false) }
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    details.frame(maxWidth: .infinity, alignment: .leading)
                    actions
                }.padding(.horizontal, 20).padding(.bottom, 22)
                GeometryReader { geometry in Capsule().fill(.white.opacity(0.25)).overlay(alignment: .leading) { Capsule().fill(Color.dogOrange).frame(width: geometry.size.width * (active ? playback.progress : 0)) } }.frame(height: 2).padding(.horizontal, 12).padding(.bottom, 3)
            }
        }.frame(width: geometry.size.width, height: geometry.size.height).background(.black).clipped()
        }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let dog {
                Button { app.selectedDog = dog } label: {
                    HStack(spacing: 9) {
                        Text(dog.name).font(.system(size: 27, weight: .bold, design: .rounded)).tracking(-0.8)
                        if dog.isFeatured { Image(systemName: "checkmark.seal.fill").font(.system(size: 15)).foregroundStyle(Color.dogOrange) }
                        Text(dog.breed.uppercased()).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1).padding(.horizontal, 8).padding(.vertical, 5).background(.white.opacity(0.15), in: Capsule())
                    }
                }.accessibilityIdentifier("feedDogName")
            }
            Text(video.caption).scaledFont(size: 15, weight: .medium).lineSpacing(4).lineLimit(3).shadow(color: .black.opacity(0.4), radius: 4, y: 1)
            Text(video.hashtags.map { "#\($0)" }.joined(separator: "  ")).scaledFont(size: 12, weight: .semibold, relativeTo: .caption).lineLimit(2).foregroundStyle(.white.opacity(0.8))
            HStack(spacing: 6) {
                Image(systemName: "waveform").font(.system(size: 11))
                Text("original sound · \(dog?.name.lowercased() ?? "tikdog")").font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                Button { playback.toggleMute() } label: { Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 12)).frame(width: 44, height: 44).background(.white.opacity(0.12), in: Circle()) }.accessibilityLabel(playback.isMuted ? "Unmute video" : "Mute video")
            }.foregroundStyle(.white.opacity(0.7))
        }.padding(.bottom, 1)
    }
    private var actions: some View {
        VStack(spacing: 22) {
            if let dog {
                ZStack(alignment: .bottom) {
                    Button { app.selectedDog = dog } label: { DogAvatar(dog: dog, size: 48) }.accessibilityLabel("View \(dog.name)'s profile")
                    if dog.ownerId != app.snapshot.userId && !app.snapshot.followingDogIds.contains(dog.id) {
                        Button { if requireMember() { Task { await app.follow(dog) } } } label: { Image(systemName: "plus").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color.dogInk).frame(width: 22, height: 22).background(Color.dogOrange, in: Circle()) }.offset(y: 10).accessibilityLabel("Follow \(dog.name)")
                    }
                }.padding(.bottom, 6)
            }
            action(icon: liked ? "heart.fill" : "heart", text: video.likeCount.compactCount, color: liked ? .dogOrange : .white, label: liked ? "Unlike video" : "Like video") { if requireMember() { Task { await app.like(video) } } }
                .accessibilityValue("\(video.likeCount.formatted()) likes")
            action(icon: "bubble.right", text: video.commentCount.compactCount, label: "Open comments", action: onComments)
                .accessibilityValue("\(video.commentCount.formatted()) comments")
            action(icon: saved ? "bookmark.fill" : "bookmark", text: "Save", color: saved ? .dogOrange : .white, label: saved ? "Unsave video" : "Save video") { if requireMember() { Task { await app.bookmark(video) } } }
            ShareLink(item: PlaybackController.mediaURL(video.playbackPath ?? video.mediaPath) ?? URL.temporaryDirectory, subject: Text("Meet \(dog?.name ?? "a very good dog") on TikDog"), message: Text(video.caption)) {
                VStack(spacing: 5) { Image(systemName: "arrowshape.turn.up.right").font(.system(size: 27, weight: .medium)); Text("Share").font(.system(size: 10, weight: .semibold)) }.frame(width: 46)
            }.disabled(video.moderationStatus != .ready || PlaybackController.mediaURL(video.playbackPath ?? video.mediaPath) == nil).accessibilityLabel("Share video")
            Button(action: onReport) { Image(systemName: "ellipsis").font(.system(size: 22, weight: .bold)).frame(width: 44, height: 44) }.accessibilityLabel("More video options")
        }.shadow(color: .black.opacity(0.3), radius: 5, y: 2)
    }
    private func action(icon: String, text: String, color: Color = .white, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { VStack(spacing: 5) { Image(systemName: icon).font(.system(size: 28, weight: .medium)).symbolEffect(.bounce, value: icon); Text(text).font(.system(size: 11, weight: .semibold)) }.foregroundStyle(color).frame(width: 46).frame(minHeight: 44) }.accessibilityLabel(label)
    }
}
