import SwiftUI
import AVKit
import TikDogCore

struct SubmissionDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let videoId: UUID
    @State private var player: AVPlayer?
    private var video: Video? { app.snapshot.videos.first { $0.id == videoId } }
    private var reviews: [ActivityItem] {
        app.snapshot.activities.filter { $0.kind == "review" && ($0.videoId == videoId || ($0.videoId == nil && $0.dogId == video?.dogId)) }
            .sorted { $0.createdAt > $1.createdAt }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let video, let dog = app.dog(for: video), dog.ownerId == app.snapshot.userId {
                        let visibility = SubmissionVisibility(video: video.moderationStatus, dog: dog.moderationStatus)
                        if let player { VideoPlayer(player: player).frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 18)) }
                        Label(visibility.title, systemImage: visibility == .publicVideo ? "checkmark.seal.fill" : "shield")
                            .font(.title2.bold()).accessibilityIdentifier("submissionDetailStatus")
                        Text(visibility.explanation).foregroundStyle(Color.dogMuted)
                        if !video.caption.isEmpty { Text(video.caption).font(.headline) }
                        LabeledContent("Featured dog", value: dog.name)
                        LabeledContent("Dog profile", value: status(dog.moderationStatus))
                        LabeledContent("Video", value: status(video.moderationStatus))
                        Text("Review updates").font(.headline)
                        if reviews.isEmpty { Text("Review decisions will appear here and in Activity.").font(.subheadline).foregroundStyle(Color.dogMuted) }
                        ForEach(reviews) { review in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(review.message)
                                Text(review.createdAt, style: .date).font(.caption).foregroundStyle(Color.dogMuted)
                            }
                        }
                        NavigationLink("Community guidelines") { LegalView(kind: "terms") }
                        NavigationLink("Contact & support") { LegalView(kind: "support") }
                    } else { ContentUnavailableView("Submission unavailable", systemImage: "video.slash", description: Text("It may have been deleted or belong to another account.")) }
                }.padding(24)
            }.background(Color.dogCream).foregroundStyle(Color.dogInk)
                .navigationTitle("Submission status").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task(id: video?.playbackPath ?? video?.mediaPath) {
                    guard let video, app.dog(for: video)?.ownerId == app.snapshot.userId,
                          let url = PlaybackController.mediaURL(video.playbackPath ?? video.mediaPath) else { return }
                    player = AVPlayer(url: url)
                }
                .refreshable { await app.load() }
                .task { await app.load() }
                .onDisappear { player?.pause() }
        }.preferredColorScheme(.light)
    }
    private func status(_ value: ContentStatus) -> String {
        switch value { case .pending: "In review"; case .ready: "Approved"; case .hidden: "Removed" }
    }
}
