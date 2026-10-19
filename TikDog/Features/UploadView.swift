import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers
import TikDogCore

struct ImportedMovie: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let destination = URL.temporaryDirectory.appendingPathComponent("import-\(UUID()).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ImportedMovie(url: destination)
        }
    }
}

@MainActor @Observable final class UploadViewModel {
    enum Stage: Equatable { case choose, edit, exporting, uploading, success }
    var stage: Stage = .choose
    var sourceURL: URL?
    var player: AVPlayer?
    var duration: Double = 0
    var trimStart: Double = 0
    var trimEnd: Double = 0
    var caption = ""
    var hashtags = ""
    var dogId: UUID?
    var progress: Double = 0
    var publishedVideo: Video?
    var error: String?
    var importing = false
    var isBusy: Bool { stage == .exporting || stage == .uploading }
    private let draftId = UUID()
    private var exportSession: AVAssetExportSession?
    private var importRequest = UUID()
    private var ownsSourceFile = false

    func choose(_ url: URL, ownsFile: Bool = true) async {
        let request = UUID(); importRequest = request
        importing = true; error = nil
        defer { if importRequest == request { importing = false } }
        do {
            let asset = AVURLAsset(url: url)
            let seconds = try await asset.load(.duration).seconds
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard request == importRequest && !Task.isCancelled else {
                if ownsFile && url != sourceURL { try? FileManager.default.removeItem(at: url) }
                return
            }
            guard seconds.isFinite, seconds >= 1, !tracks.isEmpty else { throw TikDogError.invalidInput("Choose a video that's at least a second long.") }
            if sourceURL != url { cleanupSource() }
            sourceURL = url; ownsSourceFile = ownsFile; duration = seconds; trimStart = 0; trimEnd = min(60, seconds)
            player = AVPlayer(url: url); player?.currentItem?.forwardPlaybackEndTime = CMTime(seconds: trimEnd, preferredTimescale: 600); player?.play(); stage = .edit
        } catch {
            if request == importRequest && !Task.isCancelled && !(error is CancellationError) { self.error = error.localizedDescription }
            if ownsFile && url != sourceURL { try? FileManager.default.removeItem(at: url) }
        }
    }
    func previewTrim() {
        player?.seek(to: CMTime(seconds: trimStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player?.currentItem?.forwardPlaybackEndTime = CMTime(seconds: trimEnd, preferredTimescale: 600); player?.play()
    }
    func publish(app: AppModel) async {
        guard !isBusy, let sourceURL, let dogId, app.requireMember() else { return }
        let session = app.sessionEpoch
        error = nil; progress = 0
        var output: URL?; var thumbnail: URL?
        defer { if let output { try? FileManager.default.removeItem(at: output) }; if let thumbnail { try? FileManager.default.removeItem(at: thumbnail) }; exportSession = nil }
        do {
            try ContentRules.validateVideo(caption: caption, duration: trimEnd - trimStart)
            stage = .exporting; player?.pause()
            let asset = AVURLAsset(url: sourceURL)
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else { throw TikDogError.invalidInput("This video format can't be exported. Try another clip.") }
            exportSession = export
            let destination = URL.temporaryDirectory.appendingPathComponent("export-\(UUID()).mp4"); output = destination
            export.outputURL = destination; export.outputFileType = .mp4; export.shouldOptimizeForNetworkUse = true
            export.timeRange = CMTimeRange(start: CMTime(seconds: trimStart, preferredTimescale: 600), duration: CMTime(seconds: trimEnd - trimStart, preferredTimescale: 600))
            let monitor = Task { @MainActor [weak self] in
                while !Task.isCancelled { self?.progress = Double(export.progress); try? await Task.sleep(for: .milliseconds(150)) }
            }
            await export.export(); monitor.cancel()
            guard session == app.sessionEpoch else { throw CancellationError() }
            guard export.status == .completed else { throw export.error ?? TikDogError.server("The video couldn't be prepared. Your draft is safe—please retry.") }
            let fileSize = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize <= 50 * 1024 * 1024 else { throw TikDogError.invalidInput("This clip is still over 50 MB. Trim it a little shorter and try again.") }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: destination)); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 720, height: 1280)
            let frame = try await generator.image(at: .zero)
            guard let jpeg = UIImage(cgImage: frame.image).jpegData(compressionQuality: 0.82) else { throw TikDogError.unavailable }
            let cover = URL.temporaryDirectory.appendingPathComponent("cover-\(UUID()).jpg"); thumbnail = cover; try jpeg.write(to: cover)
            guard session == app.sessionEpoch else { throw CancellationError() }
            let draft = Video(id: draftId, dogId: dogId, caption: caption.trimmingCharacters(in: .whitespacesAndNewlines), hashtags: ContentRules.hashtags(from: hashtags), mediaPath: "", duration: trimEnd - trimStart)
            stage = .uploading; progress = 0
            let published = try await app.repository.publish(draft, file: destination, thumbnail: cover) { [weak self] value in
                Task { @MainActor [weak self] in
                    guard session == app.sessionEpoch, self?.stage == .uploading else { return }
                    self?.progress = value
                }
            }
            guard session == app.sessionEpoch else { throw CancellationError() }
            app.mergeLocal(videos: [published]); await app.loadFeed(reset: true, kind: .forYou)
            guard session == app.sessionEpoch else { throw CancellationError() }
            publishedVideo = published
            if published.moderationStatus == .ready { app.feedIds[.forYou]?.removeAll { $0 == published.id }; app.feedIds[.forYou, default: []].insert(published.id, at: 0) }
            progress = 1; stage = .success; Haptics.like(); cleanupSource()
        } catch {
            if session == app.sessionEpoch && !(error is CancellationError) { self.error = error.localizedDescription }
            stage = .edit
        }
    }
    func cleanup() { importRequest = UUID(); importing = false; player?.pause(); player = nil; exportSession?.cancelExport(); cleanupSource() }
    private func cleanupSource() {
        if ownsSourceFile, let sourceURL, sourceURL.path.hasPrefix(URL.temporaryDirectory.path) { try? FileManager.default.removeItem(at: sourceURL) }
        sourceURL = nil; ownsSourceFile = false
    }
}

struct UploadView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model = UploadViewModel()
    @State private var selection: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showDogEditor = false
    @State private var confirmDiscard = false
    @FocusState private var focused: Bool
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.stage == .success { success }
                else if model.stage == .choose { choose }
                else { editor }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.dogCream).foregroundStyle(Color.dogInk)
                .navigationTitle(model.stage == .choose ? "A star is born" : "Their next big moment").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button { if model.stage == .edit { confirmDiscard = true } else { dismiss() } } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)) }.disabled(model.isBusy).accessibilityLabel("Close upload") }
                    if app.isDemo { ToolbarItem(placement: .topBarTrailing) { Text("DEMO").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(Color.dogMuted) } }
                }
                .interactiveDismissDisabled(model.isBusy || model.stage == .edit)
                .alert("Discard this draft?", isPresented: $confirmDiscard) { Button("Discard", role: .destructive) { dismiss() }; Button("Keep editing", role: .cancel) {} }
                .sheet(isPresented: $showCamera) { CameraPicker { url in showCamera = false; if let url { Task { await model.choose(url) } } } }
                .sheet(isPresented: $showDogEditor) { DogEditorView(dog: nil) { model.dogId = $0.id } }
                .task(id: selection) {
                    guard let selection else { return }; model.importing = true
                    do { guard let movie = try await selection.loadTransferable(type: ImportedMovie.self) else { throw TikDogError.invalidInput("Couldn't open that video.") }; await model.choose(movie.url) } catch { model.error = error.localizedDescription; model.importing = false }
                }
                .onAppear { if model.dogId == nil { model.dogId = app.selectedOwnDog?.id } }
                .onChange(of: app.ownDogs.map(\.id)) { _, _ in if model.dogId == nil { model.dogId = app.selectedOwnDog?.id } }
                .onDisappear { model.cleanup() }
        }.preferredColorScheme(.light).tint(.dogInk)
    }
    private var choose: some View {
        VStack(spacing: 25) {
            Spacer()
            Image(systemName: "video.badge.plus").font(.system(size: 48, weight: .light)).foregroundStyle(Color.dogOrange).padding(28).background(Color.dogOrange.opacity(0.1), in: RoundedRectangle(cornerRadius: 35)).rotationEffect(.degrees(-6))
            Text("Big personality.\nLittle screen.").font(.system(size: 35, weight: .bold, design: .rounded)).tracking(-1.1).multilineTextAlignment(.center)
            Text("The zoomies. The side-eye. The everyday magic.\nShare a little of their world.").font(.system(size: 13)).foregroundStyle(Color.dogMuted).lineSpacing(5).multilineTextAlignment(.center)
            if model.importing { ProgressView("Getting your video ready…").font(.caption).padding() }
            else {
                VStack(spacing: 12) {
                    PhotosPicker(selection: $selection, matching: .videos) { Label("Choose a video", systemImage: "photo.on.rectangle") }.buttonStyle(PrimaryButtonStyle())
                    Button { if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true } else { model.error = "Recording needs an iPhone camera. Choose a video or try the demo clip." } } label: { Label("Record a moment", systemImage: "camera") }.buttonStyle(PrimaryButtonStyle(dark: true))
                    if app.isDemo { Button("Try with a demo clip") { if let url = Bundle.main.url(forResource: "cabby", withExtension: "mp4") { Task { await model.choose(url, ownsFile: false) } } }.font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.dogMuted).padding(.top, 6).accessibilityIdentifier("useDemoClip") }
                }.padding(.top, 6)
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center) }
            Spacer()
            Text("DOGS FIRST. ALWAYS.").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Color.dogMuted).padding(.bottom, 20)
        }.padding(.horizontal, 30)
    }
    private var editor: some View {
        @Bindable var model = model
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 18) {
                    VideoPlayer(player: model.player).frame(width: 124, height: 199).clipShape(RoundedRectangle(cornerRadius: 19))
                    VStack(alignment: .leading, spacing: 11) {
                        Text("LET THEM SHINE").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(Color.dogMuted)
                        Text("Who's the star?").font(.system(size: 22, weight: .bold, design: .rounded)).tracking(-0.6)
                        if app.ownDogs.isEmpty { Button("Add your dog first") { showDogEditor = true }.font(.subheadline.bold()) }
                        else { Picker("Featured dog", selection: $model.dogId) { ForEach(app.ownDogs) { dog in Text(dog.name).tag(Optional(dog.id)) } }.pickerStyle(.menu).labelsHidden().padding(4).background(.white, in: Capsule()).accessibilityIdentifier("featuredDogPicker") }
                        Text("Only share videos you own and keep your dog safe.").font(.system(size: 11)).foregroundStyle(Color.dogMuted).lineSpacing(4)
                    }.padding(.top, 12)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Label("Find the good part", systemImage: "scissors").font(.system(size: 13, weight: .bold)); Spacer(); Text(String(format: "%.1fs", model.trimEnd - model.trimStart)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Color.dogMuted) }
                    HStack { Text("Start").frame(width: 35, alignment: .leading); Slider(value: $model.trimStart, in: 0...max(0.01, model.trimEnd - 1), step: 0.1) { editing in if !editing { model.previewTrim() } }; Text(String(format: "%.1f", model.trimStart)).monospacedDigit().frame(width: 35) }.font(.system(size: 11)).tint(.dogOrange)
                    HStack { Text("End").frame(width: 35, alignment: .leading); Slider(value: $model.trimEnd, in: min(model.duration, model.trimStart + 1)...min(model.duration, model.trimStart + 60), step: 0.1) { editing in if !editing { model.previewTrim() } }; Text(String(format: "%.1f", model.trimEnd)).monospacedDigit().frame(width: 35) }.font(.system(size: 11)).tint(.dogOrange)
                    Text("1–60 seconds of pure good dog.").font(.system(size: 10)).foregroundStyle(Color.dogMuted)
                }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tell their story").font(.system(size: 14, weight: .bold))
                    TextField("What's the little legend up to?", text: $model.caption, axis: .vertical).lineLimit(3...5).font(.system(size: 14)).focused($focused).accessibilityIdentifier("uploadCaption")
                    HStack { Spacer(); Text("\(model.caption.count)/300").font(.system(size: 10)).foregroundStyle(model.caption.count > 300 ? .red : Color.dogMuted) }
                }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                HStack { Text("#").font(.system(size: 22)).foregroundStyle(Color.dogOrange); TextField("cavapoo  walkies  gooddog", text: $model.hashtags).font(.system(size: 13)).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("uploadHashtags") }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18))
                if model.isBusy {
                    VStack(spacing: 9) { ProgressView(value: model.progress).tint(.dogOrange); HStack { Text(model.stage == .exporting ? "Preparing their close-up…" : "Sharing with the pack…"); Spacer(); Text("\(Int(model.progress * 100))%") }.font(.system(size: 11)).foregroundStyle(Color.dogMuted) }
                }
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).lineSpacing(3) }
                Button { focused = false; Task { await model.publish(app: app) } } label: { Label(model.error == nil ? "Let them shine" : "Try again", systemImage: "arrow.up.right") }.buttonStyle(PrimaryButtonStyle()).disabled(model.isBusy || model.dogId == nil || model.caption.count > 300).accessibilityIdentifier("publishVideo")
                Text("New videos are reviewed before appearing publicly.").font(.caption).foregroundStyle(Color.dogMuted)
                if app.isDemo { Text("Demo uploads are saved on this device.").font(.system(size: 10)).foregroundStyle(Color.dogMuted).frame(maxWidth: .infinity) }
            }.padding(24).disabled(model.isBusy)
        }.scrollDismissesKeyboard(.interactively)
    }
    private var success: some View {
        VStack(spacing: 23) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 70)).foregroundStyle(Color.dogOrange)
            Text("Hello, little superstar.").font(.system(size: 30, weight: .bold, design: .rounded)).tracking(-1).multilineTextAlignment(.center)
            Text("Their video is awaiting review. It will appear publicly after approval.").font(.system(size: 13)).foregroundStyle(Color.dogMuted)
            Button("See in my profile") {
                if let video = model.publishedVideo { app.selectedOwnDogId = video.dogId }
                app.selectedTab = .profile; dismiss()
            }.buttonStyle(PrimaryButtonStyle()).padding(.top, 10).accessibilityIdentifier("uploadSuccess")
        }.padding(35)
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let completion: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.delegate = context.coordinator; picker.sourceType = .camera; picker.mediaTypes = [UTType.movie.identifier]; picker.cameraCaptureMode = .video; picker.videoMaximumDuration = 60; picker.videoQuality = .typeHigh; return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (URL?) -> Void
        init(completion: @escaping (URL?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let original = info[.mediaURL] as? URL else { completion(nil); return }
            let copy = URL.temporaryDirectory.appendingPathComponent("record-\(UUID()).mov")
            do { try FileManager.default.copyItem(at: original, to: copy); completion(copy) } catch { completion(nil) }
        }
    }
}
