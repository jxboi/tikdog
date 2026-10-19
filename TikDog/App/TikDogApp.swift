import SwiftUI
import AVFoundation
import TikDogCore

@main struct TikDogApp: App {
    @State private var app = AppModel.configured()
    init() { try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers]) }
    var body: some Scene { WindowGroup { RootView().environment(app).tint(.dogOrange).task { await app.load() } } }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .top) {
            if app.configurationError == nil {
                VStack(spacing: 0) {
                    Group {
                        switch app.selectedTab {
                        case .home: FeedView()
                        case .discover: DiscoverView()
                        case .upload: FeedView()
                        case .activity: ActivityView()
                        case .profile: MyProfileView()
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    bottomBar
                }.background(app.selectedTab == .home ? .black : Color.dogCream)
            }
            if let configurationError = app.configurationError {
                ContentUnavailableView("TikDog is unavailable", systemImage: "wifi.exclamationmark", description: Text(configurationError))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.dogCream).zIndex(20)
            }
            if let toast = app.toast {
                Label(toast, systemImage: "checkmark.circle.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.dogInk)
                    .padding(.horizontal, 18).padding(.vertical, 14).background(.regularMaterial, in: Capsule()).shadow(color: .black.opacity(0.1), radius: 16, y: 6).padding(.top, 10).padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity)).zIndex(10).accessibilityIdentifier("toast")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.toast)
        .preferredColorScheme(app.configurationError == nil && app.selectedTab == .home ? .dark : .light)
        .sheet(isPresented: $app.isUploadPresented) { UploadView().environment(app).preferredColorScheme(.light) }
        .sheet(isPresented: $app.showAuth) { AuthView().environment(app).preferredColorScheme(.light).presentationDragIndicator(.visible) }
        .sheet(isPresented: $app.showTerms) { TermsConsentView() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await app.load() } } }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(600)) } catch { break }
                if scenePhase == .active { await app.load() }
            }
        }
        .sheet(item: $app.selectedDog) { dog in NavigationStack { DogProfileView(dog: dog) }.preferredColorScheme(.light).presentationDragIndicator(.visible) }
        .fullScreenCover(item: $app.selectedVideo) { video in FeedView(standaloneVideos: app.snapshot.videos.filter { $0.dogId == video.dogId }, initialVideo: video.id, isStandalone: true).environment(app).preferredColorScheme(.dark) }
        .alert("A little hiccup", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) { Button("OK", role: .cancel) { app.errorMessage = nil } } message: { Text(app.errorMessage ?? "") }
        .onChange(of: app.selectedTab) { _, _ in Haptics.selection() }
    }
    private var bottomBar: some View {
        let dark = app.selectedTab == .home
        return HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    if tab == .upload { app.presentUpload() }
                    else { app.selectedTab = tab }
                } label: {
                    if tab == .upload {
                        Image(systemName: "plus").font(.system(size: 22, weight: .bold)).foregroundStyle(Color.dogInk)
                            .frame(width: 51, height: 36).background(Color.dogOrange, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(dark ? 0.25 : 0), lineWidth: 1)).frame(maxWidth: .infinity).frame(height: 58)
                    } else {
                        VStack(spacing: 5) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: tab.icon).font(.system(size: 21, weight: app.selectedTab == tab ? .semibold : .regular))
                                if tab == .activity && app.unreadCount > 0 { Circle().fill(Color.dogOrange).frame(width: 5, height: 5).offset(x: 4, y: -1) }
                            }
                            Text(tab.rawValue).font(.system(size: 9, weight: app.selectedTab == tab ? .bold : .medium))
                        }.foregroundStyle(app.selectedTab == tab ? (dark ? .white : Color.dogInk) : (dark ? .white.opacity(0.5) : Color.dogMuted)).frame(maxWidth: .infinity).frame(height: 58)
                    }
                }.accessibilityLabel(tab == .upload ? "Upload video" : tab.rawValue)
                    .accessibilityValue(tab == .activity ? (app.unreadCount == 0 ? "No unread notifications" : "\(app.unreadCount) unread notifications") : "")
                    .accessibilityIdentifier("tab-\(tab.rawValue.lowercased())").accessibilityAddTraits(app.selectedTab == tab ? .isSelected : [])
            }
        }.padding(.horizontal, 12).padding(.top, 5).background(dark ? .black : Color.dogCream)
            .overlay(alignment: .top) { Rectangle().fill(dark ? .white.opacity(0.1) : Color.dogInk.opacity(0.07)).frame(height: 0.5) }
    }
}
