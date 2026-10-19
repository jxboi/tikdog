import SwiftUI
import TikDogCore

@MainActor @Observable final class CommentsViewModel {
    var comments: [DogComment] = []
    var draft = ""
    var isLoading = true
    var isSending = false
    var error: String?
    private var loadRequest = UUID()
    private var postedDuringLoad: [DogComment] = []
    func load(video: Video, repository: any TikDogRepository) async {
        let request = UUID(); loadRequest = request
        postedDuringLoad = []
        isLoading = true; error = nil
        defer { if loadRequest == request { isLoading = false } }
        do {
            let latest = try await repository.comments(videoId: video.id)
            guard !Task.isCancelled && loadRequest == request else { return }
            let ids = Set(latest.map(\.id))
            comments = latest + postedDuringLoad.filter { !ids.contains($0.id) }
        } catch {
            guard !Task.isCancelled && !(error is CancellationError) && loadRequest == request else { return }
            self.error = error.localizedDescription
        }
    }
    func send(video: Video, app: AppModel) async {
        let submitted = draft
        guard !submitted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, app.requireMember(), !isSending else { return }
        let epoch = app.sessionEpoch
        isSending = true; error = nil; defer { isSending = false }
        do {
            let comment = try await app.repository.addComment(videoId: video.id, body: submitted)
            guard epoch == app.sessionEpoch else { return }
            if isLoading { postedDuringLoad.append(comment) }
            if !comments.contains(where: { $0.id == comment.id }) { comments.append(comment) }
            if draft == submitted { draft = "" }
            if comment.moderationStatus == .ready {
                app.applyLocalChange { state in
                    if let index = state.videos.firstIndex(where: { $0.id == video.id }) { state.videos[index].commentCount += 1 }
                }
            }
            Haptics.selection()
        } catch { if epoch == app.sessionEpoch && !(error is CancellationError) { self.error = error.localizedDescription } }
    }
}
struct CommentsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    let video: Video
    @State private var model = CommentsViewModel()
    @FocusState private var focused: Bool
    @State private var localAuth = false
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack { Text("A little love for \(app.dog(for: video)?.name ?? "this dog")").scaledFont(size: 19, weight: .bold, design: .rounded, relativeTo: .headline).lineLimit(2); Spacer(); Text("\(model.comments.count)").font(.caption.bold()).foregroundStyle(Color.dogMuted); Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 32, height: 32).background(.black.opacity(0.04), in: Circle()).frame(width: 44, height: 44) }.accessibilityLabel("Close comments") }.padding(24)
            if model.isLoading { ProgressView().frame(maxHeight: .infinity) }
            else if model.comments.isEmpty && model.error != nil {
                VStack(spacing: 12) {
                    EmptyState(icon: "wifi.exclamationmark", title: "Comments couldn't load", message: "Try again when you're connected.")
                    Button("Try again") { Task { await model.load(video: video, repository: app.repository) } }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 40).padding(.bottom, 24)
                }
            }
            else if model.comments.isEmpty { EmptyState(icon: "bubble.left.and.bubble.right", title: "Start the conversation", message: "A kind word goes a long way. Leave the first comment.") }
            else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(model.comments) { comment in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "pawprint.fill").font(.system(size: 16)).foregroundStyle(Color.dogOrange).frame(width: 38, height: 38).background(Color.dogOrange.opacity(0.1), in: Circle())
                                    VStack(alignment: .leading, spacing: 5) {
                                        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3)) : AnyLayout(HStackLayout())
                                        layout {
                                            Text(comment.author).scaledFont(size: 12, weight: .bold, relativeTo: .caption)
                                            Text(comment.createdAt, style: .relative).scaledFont(size: 10, relativeTo: .caption2).foregroundStyle(Color.dogMuted)
                                        }
                                        Text(comment.body).scaledFont(size: 14).lineSpacing(3)
                                        if comment.moderationStatus != .ready { Text("Awaiting review · Only you can see this").font(.caption2).foregroundStyle(Color.dogMuted) }
                                    }
                                    Spacer(minLength: 0)
                                    if comment.userId != app.snapshot.userId {
                                        Menu {
                                            Button("Report comment") { if app.requireMember() { Task {
                                                do { try await app.repository.reportContent(kind: .comment, id: comment.id, reason: "inappropriate"); model.comments.removeAll { $0.id == comment.id }; app.notify("Comment reported and hidden") }
                                                catch { model.error = error.localizedDescription }
                                            } } }
                                            Button("Block this account", role: .destructive) { if app.requireMember() { Task {
                                                do { try await app.blockOwner(comment.userId); model.comments.removeAll { $0.userId == comment.userId } }
                                                catch { model.error = error.localizedDescription }
                                            } } }
                                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Comment options")
                                    }
                                }.id(comment.id)
                            }
                        }.padding(.horizontal, 24).padding(.bottom, 24)
                    }.scrollDismissesKeyboard(.interactively).onChange(of: model.comments.count) { _, _ in if let last = model.comments.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
                }
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 24) }
            if app.snapshot.userId == nil {
                Button("Join the pack to comment") { localAuth = true }.buttonStyle(PrimaryButtonStyle()).padding(20)
            } else {
            HStack(spacing: 12) {
                TextField("Say something kind…", text: $model.draft).scaledFont(size: 14).frame(minHeight: 44).focused($focused).submitLabel(.send).onSubmit { Task { await model.send(video: video, app: app) } }.onChange(of: model.draft) { _, value in if value.count > 500 { model.draft = String(value.prefix(500)) } }.accessibilityIdentifier("commentDraft")
                Button { focused = false; Task { await model.send(video: video, app: app) } } label: {
                    if model.isSending { ProgressView().tint(Color.dogInk).frame(width: 38, height: 38) }
                    else { Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.dogInk).frame(width: 38, height: 38).background(Color.dogOrange, in: Circle()) }
                }.frame(width: 44, height: 44).disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSending || model.isLoading).accessibilityLabel("Post comment")
            }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 20).padding(.vertical, 14)
            }
        }.background(Color.dogCream).foregroundStyle(Color.dogInk).preferredColorScheme(.light)
            .sheet(isPresented: $localAuth) { AuthView() }
            .task(id: app.dataEpoch) { await model.load(video: video, repository: app.repository) }
    }
}
