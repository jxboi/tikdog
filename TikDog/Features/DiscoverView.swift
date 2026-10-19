import SwiftUI
import TikDogCore

struct DiscoverView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var query = ""
    @State private var results: [Dog] = []
    @State private var searching = false
    @State private var searchError: String?
    @State private var showVoting = false
    @State private var selectedTag: String?
    @FocusState private var searchFocused: Bool
    private var searchQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var dogs: [Dog] {
        searchQuery.isEmpty ? app.visibleDogs : results.filter { dog in app.visibleDogs.contains { $0.id == dog.id } }
    }
    private var trendingTags: [(String, Int)] {
        let all = app.visibleVideos.flatMap(\.hashtags)
        let grouped: [String: [String]] = Dictionary(grouping: all, by: { $0 })
        let counts: [(String, Int)] = grouped.map { ($0.key, $0.value.count) }
        let ranked = counts.sorted { a, b in a.1 == b.1 ? a.0 < b.0 : a.1 > b.1 }
        return Array(ranked.prefix(6))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Discover").scaledFont(size: 32, weight: .bold, design: .rounded, relativeTo: .largeTitle).tracking(-1)
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Color.dogMuted)
                        TextField("Search by name or breed", text: $query).font(.body).autocorrectionDisabled().textInputAutocapitalization(.never).submitLabel(.search).focused($searchFocused).onSubmit { searchFocused = false }.accessibilityLabel("Search dogs by name or breed").accessibilityIdentifier("dogSearch")
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.dogMuted).frame(width: 44, height: 44) }.accessibilityLabel("Clear search") }
                    }.frame(minHeight: 44).padding(.horizontal, 16).padding(.vertical, 6).background(.white, in: RoundedRectangle(cornerRadius: 17))
                    if searchQuery.isEmpty && !app.visibleDogs.isEmpty {
                        if !trendingTags.isEmpty {
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(trendingTags, id: \.0) { tag in
                                        Button { selectedTag = tag.0 } label: {
                                            Text("#\(tag.0)").font(.subheadline.weight(.medium))
                                                .padding(.horizontal, 14).frame(minHeight: 44)
                                                .background(.white, in: Capsule())
                                        }
                                    }
                                }
                            }.scrollIndicators(.hidden)
                        }
                        Button { showVoting = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "crown.fill").font(.system(size: 20)).foregroundStyle(Color.dogOrange)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Dog of the Day").font(.subheadline.weight(.semibold))
                                    if dynamicTypeSize.isAccessibilitySize {
                                        Text(app.snapshot.votedDogId == nil ? "Vote" : "View results").font(.subheadline)
                                    }
                                }.fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                if !dynamicTypeSize.isAccessibilitySize {
                                    Text(app.snapshot.votedDogId == nil ? "Vote" : "View results").font(.subheadline)
                                }
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                            }.padding(16).background(Color.dogOrange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                        }.accessibilityIdentifier("dailyVoteEntry")
                    }
                    VStack(alignment: .leading, spacing: 17) {
                        Text(searchQuery.isEmpty ? "Meet the dogs" : "Search results").font(.headline)
                        if searching { ProgressView().frame(maxWidth: .infinity).padding() }
                        else if let searchError { Text(searchError).font(.subheadline).foregroundStyle(.red) }
                        else if dogs.isEmpty {
                            if searchQuery.isEmpty {
                                EmptyState(icon: "pawprint", title: "The pack is growing", message: "Dog profiles appear here after review. Give your dog their first moment while the pack grows.")
                                Button("Add my dog") { app.presentDogCreation() }.buttonStyle(PrimaryButtonStyle())
                            } else { EmptyState(icon: "magnifyingglass", title: "No tails found", message: "Try another name or breed. Your new favorite is out there.") }
                        }
                        else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 20) {
                                ForEach(searchQuery.isEmpty ? dogs.sorted { $0.followerCount < $1.followerCount } : dogs) { dog in dogCard(dog) }
                            }
                        }
                    }
                }.padding(.horizontal, 22).padding(.top, 25).padding(.bottom, 18)
            }.background(Color.dogCream).foregroundStyle(Color.dogInk).toolbar(.hidden, for: .navigationBar).scrollDismissesKeyboard(.interactively)
                .refreshable { await app.load() }
                .task(id: "\(searchQuery)-\(app.dataEpoch)-\(app.stateRevision)") {
                    let term = searchQuery
                    guard !term.isEmpty else { results = []; searching = false; searchError = nil; return }
                    let epoch = app.dataEpoch, revision = app.stateRevision
                    searching = true; searchError = nil
                    do {
                        try await Task.sleep(for: .milliseconds(280))
                        let matches = try await app.repository.discover(query: term)
                        guard !Task.isCancelled && epoch == app.dataEpoch && revision == app.stateRevision else { return }; results = matches; app.merge(dogs: matches); searching = false
                    } catch {
                        guard !Task.isCancelled && epoch == app.dataEpoch && revision == app.stateRevision else { return }
                        searchError = error.localizedDescription; searching = false
                    }
                }
                .sheet(isPresented: $showVoting) { VotingView().presentationDragIndicator(.visible) }
                .sheet(item: Binding(get: { selectedTag.map(TagSelection.init) }, set: { selectedTag = $0?.value })) { tag in
                    TagVideosView(tag: tag.value).presentationDragIndicator(.visible)
                }
        }
    }
    private func dogCard(_ dog: Dog) -> some View {
        Button { app.selectedDog = dog } label: {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geometry in
                    MediaImage(path: dog.displayAvatarPath ?? dog.avatarPath)
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }.aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text(dog.name).scaledFont(size: 18, weight: .bold, design: .rounded, relativeTo: .headline)
                    Text(dog.breed).font(.subheadline).foregroundStyle(Color.dogMuted)
                }.multilineTextAlignment(.leading)
            }
        }
    }
}
private struct TagVideosView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let tag: String
    @State private var selectedVideo: Video?
    private var videos: [Video] { app.visibleVideos.filter { $0.hashtags.contains(tag) } }
    var body: some View {
        NavigationStack {
            ScrollView { VideoGrid(videos: videos, onSelect: { selectedVideo = $0 }) }
                .background(Color.dogCream).navigationTitle("#\(tag)").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
            .fullScreenCover(item: $selectedVideo) { video in FeedView(standaloneVideos: videos, initialVideo: video.id, isStandalone: true).preferredColorScheme(.dark) }
    }
}
private struct TagSelection: Identifiable { let value: String; var id: String { value } }

struct VotingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var showingWinners = false
    @State private var localAuth = false
    private var standings: [DailyStanding] { app.snapshot.standings.sorted { showingWinners ? ($0.wins == $1.wins ? $0.votes > $1.votes : $0.wins > $1.wins) : $0.votes > $1.votes } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "crown.fill").font(.system(size: 46)).foregroundStyle(Color.dogOrange).padding(.top, 20)
                    Text("One vote each day. Choose your favorite.").font(.system(size: 13)).lineSpacing(5).foregroundStyle(Color.dogMuted).multilineTextAlignment(.center)
                    Picker("Leaderboard", selection: $showingWinners) { Text("Today's vote").tag(false); Text("Hall of fame").tag(true) }.pickerStyle(.segmented)
                    ForEach(Array(standings.enumerated()), id: \.element.id) { index, entry in
                        if let dog = app.visibleDogs.first(where: { $0.id == entry.dogId }) {
                            HStack(spacing: 13) {
                                Text(String(format: "%02d", index + 1)).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(Color.dogMuted).frame(width: 24)
                                Button { app.selectedDog = dog; dismiss() } label: { DogAvatar(dog: dog, size: 50) }
                                VStack(alignment: .leading, spacing: 5) { Text(dog.name).font(.system(size: 16, weight: .bold, design: .rounded)); Text(showingWinners ? "\(entry.wins) daily wins" : "\(entry.votes) votes today").font(.system(size: 11)).foregroundStyle(Color.dogMuted) }
                                Spacer()
                                if !showingWinners {
                                    Button { if app.snapshot.userId == nil { localAuth = true } else { Task { await app.vote(dog) } } } label: {
                                        Text(app.snapshot.votedDogId == dog.id ? "Voted ✓" : "Vote").font(.system(size: 12, weight: .bold)).padding(.horizontal, 15).padding(.vertical, 11).background(app.snapshot.votedDogId == dog.id ? Color.dogInk : Color.dogOrange.opacity(0.25), in: Capsule()).foregroundStyle(app.snapshot.votedDogId == dog.id ? .white : Color.dogInk)
                                    }.disabled(app.snapshot.votedDogId != nil || app.pendingActions.contains("vote")).accessibilityIdentifier("vote-\(dog.name.lowercased())")
                                } else { Image(systemName: "rosette").foregroundStyle(Color.dogOrange) }
                            }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                    Text("Voting resets at midnight UTC. Winners are counted from completed days.").font(.system(size: 10)).foregroundStyle(Color.dogMuted).multilineTextAlignment(.center).padding(.bottom, 20)
                }.padding(22)
            }.background(Color.dogCream).foregroundStyle(Color.dogInk).navigationTitle("Dog of the Day").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.light).task { await app.refreshVoting() }.sheet(isPresented: $localAuth) { AuthView() }
    }
}
