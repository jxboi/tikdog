import SwiftUI
import TikDogCore

struct DiscoverView: View {
    @Environment(AppModel.self) private var app
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
    private var heroDog: Dog? { app.visibleDogs.first { $0.id == app.snapshot.standings.max(by: { $0.votes < $1.votes })?.dogId } ?? app.visibleDogs.first }
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
                VStack(alignment: .leading, spacing: 29) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("GOOD DOGS. GREAT COMPANY.").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Color.dogMuted)
                            Text("Find your pack.").font(.system(size: 35, weight: .bold, design: .rounded)).tracking(-1.5)
                        }
                        Spacer(); Image(systemName: "pawprint.fill").font(.system(size: 25)).rotationEffect(.degrees(15)).foregroundStyle(Color.dogOrange).padding(.top, 19)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Color.dogMuted)
                        TextField("A name, a breed, a new best friend…", text: $query).font(.system(size: 13)).autocorrectionDisabled().textInputAutocapitalization(.never).submitLabel(.search).focused($searchFocused).onSubmit { searchFocused = false }.accessibilityLabel("Search dogs by name or breed").accessibilityIdentifier("dogSearch")
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.dogMuted).frame(width: 44, height: 44) }.accessibilityLabel("Clear search") }
                    }.frame(minHeight: 44).padding(.horizontal, 16).padding(.vertical, 6).background(.white, in: RoundedRectangle(cornerRadius: 17))
                    if searchQuery.isEmpty && !app.visibleDogs.isEmpty {
                        if let dog = heroDog { votingHero(dog) }
                        VStack(alignment: .leading, spacing: 19) {
                            HStack { SectionLabel(title: "Little dogs. Big energy.", eyebrow: "Your next favorite"); Spacer() }
                            ScrollView(.horizontal) {
                                HStack(alignment: .top, spacing: 24) {
                                    ForEach(app.visibleDogs.sorted { $0.followerCount < $1.followerCount }) { dog in
                                        Button { app.selectedDog = dog } label: {
                                            VStack(spacing: 9) {
                                                DogAvatar(dog: dog, size: 73, ring: true)
                                                Text(dog.name).font(.system(size: 13, weight: .bold))
                                                Text(dog.breed).font(.system(size: 10)).foregroundStyle(Color.dogMuted)
                                            }.frame(width: 76)
                                        }
                                    }
                                }.padding(.vertical, 2)
                            }.scrollIndicators(.hidden)
                        }
                        VStack(alignment: .leading, spacing: 15) {
                            SectionLabel(title: "What's wagging", eyebrow: "Explore the good stuff")
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(Array(trendingTags.enumerated()), id: \.element.0) { index, tag in
                                    Button { selectedTag = tag.0 } label: {
                                        HStack(spacing: 9) {
                                            Text("#").font(.system(size: 25, weight: .light)).foregroundStyle(Color.dogOrange)
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(tag.0).font(.system(size: 11, weight: .bold)).lineLimit(1)
                                                Text("\(tag.1) adventures").font(.system(size: 10)).foregroundStyle(Color.dogMuted)
                                            }
                                            Spacer(minLength: 0)
                                            Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(Color.dogMuted)
                                        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 15))
                                    }
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 17) {
                        SectionLabel(title: searchQuery.isEmpty ? "Made to be adored." : "Meet the good dogs", eyebrow: searchQuery.isEmpty ? "Community favorites" : "Search results")
                        if searching { ProgressView().frame(maxWidth: .infinity).padding() }
                        else if let searchError { Text(searchError).font(.subheadline).foregroundStyle(.red) }
                        else if dogs.isEmpty {
                            if searchQuery.isEmpty {
                                EmptyState(icon: "pawprint", title: "The pack is growing", message: "Dog profiles appear here after review. Give your dog their first moment while the pack grows.")
                                Button("Meet my dog") { app.selectedTab = .profile }.buttonStyle(PrimaryButtonStyle())
                            } else { EmptyState(icon: "magnifyingglass", title: "No tails found", message: "Try another name or breed. Your new favorite is out there.") }
                        }
                        else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                                ForEach(dogs) { dog in dogCard(dog) }
                            }
                        }
                    }
                    HStack(spacing: 7) { Image(systemName: "heart.fill").foregroundStyle(Color.dogOrange); Text("Every dog deserves their moment.").foregroundStyle(Color.dogMuted) }.font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 10)
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
    private func votingHero(_ dog: Dog) -> some View {
        Button { showVoting = true } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 11) {
                    Label("DOG OF THE DAY", systemImage: "crown.fill").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.4)
                    Text("A little fame.\nA lot of good dog.").font(.system(size: 25, weight: .bold, design: .rounded)).tracking(-0.8).lineSpacing(1).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) { Text("Cast your daily vote").font(.system(size: 11, weight: .bold)); Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)) }.padding(.top, 4)
                }.padding(.leading, 21).padding(.vertical, 24).frame(maxWidth: .infinity, alignment: .leading)
                MediaImage(path: dog.displayAvatarPath ?? dog.avatarPath).frame(width: 126, height: 188).clipShape(UnevenRoundedRectangle(topLeadingRadius: 60, bottomLeadingRadius: 60)).overlay(alignment: .bottom) { Text(dog.name).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 6).background(.black.opacity(0.3), in: Capsule()).padding(.bottom, 14) }
            }.background(Color(red: 1, green: 0.79, blue: 0.63)).clipShape(RoundedRectangle(cornerRadius: 24))
        }.accessibilityIdentifier("dailyVoteHero")
    }
    private func dogCard(_ dog: Dog) -> some View {
        Button { app.selectedDog = dog } label: {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geometry in MediaImage(path: dog.displayAvatarPath ?? dog.avatarPath).frame(width: geometry.size.width, height: geometry.size.height).clipped() }.frame(height: 174).clipShape(RoundedRectangle(cornerRadius: 19))
                    .overlay(alignment: .topTrailing) { Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).padding(10).background(.black.opacity(0.18), in: Circle()).padding(9) }
                HStack { Text(dog.name).font(.system(size: 17, weight: .bold, design: .rounded)); if dog.isFeatured { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.dogOrange).font(.system(size: 11)) }; Spacer() }
                HStack { Text(dog.breed); Spacer(); Text("\(dog.followerCount.compactCount) fans") }.font(.system(size: 10)).foregroundStyle(Color.dogMuted).lineLimit(1)
            }
        }
    }
}
private struct TagVideosView: View {
    @Environment(AppModel.self) private var app
    let tag: String
    @State private var selectedVideo: Video?
    private var videos: [Video] { app.visibleVideos.filter { $0.hashtags.contains(tag) } }
    var body: some View {
        NavigationStack { ScrollView { VideoGrid(videos: videos, onSelect: { selectedVideo = $0 }) }.background(Color.dogCream).navigationTitle("#\(tag)").navigationBarTitleDisplayMode(.inline) }
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
                    Text("Who's a very good dog?").font(.system(size: 29, weight: .bold, design: .rounded)).tracking(-1).multilineTextAlignment(.center)
                    Text("One person. One vote. Every day.\nA fresh chance for every little star.").font(.system(size: 13)).lineSpacing(5).foregroundStyle(Color.dogMuted).multilineTextAlignment(.center)
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
