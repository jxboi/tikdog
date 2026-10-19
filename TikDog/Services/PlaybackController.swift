import SwiftUI
import AVFoundation
import TikDogCore

@MainActor @Observable final class PlaybackController {
    private var players: [UUID: AVQueuePlayer] = [:]
    private var loopers: [UUID: AVPlayerLooper] = [:]
    private var playerPaths: [UUID: String] = [:]
    private var timeObserver: Any?
    private var observedPlayer: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var currentItemObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var observationId = UUID()
    private var pendingSeek: CMTime?
    private(set) var activeId: UUID?
    var isPaused = false
    var isMuted = true
    var progress: Double = 0
    var isBuffering = false
    var playbackError: String?

    func player(for id: UUID) -> AVQueuePlayer? { players[id] }
    func activate(_ video: Video?, in videos: [Video]) {
        guard let video, let index = videos.firstIndex(where: { $0.id == video.id }) else { stop(); return }
        let resumeTime = activeId == video.id && playerPaths[video.id] != (video.playbackPath ?? video.mediaPath) ? (pendingSeek ?? players[video.id]?.currentTime()) : nil
        let keep = Set(videos[max(0, index-1)...min(videos.count-1, index+2)].map(\.id))
        for id in Array(players.keys) {
            let currentPath = videos.first { $0.id == id }.map { $0.playbackPath ?? $0.mediaPath }
            if !keep.contains(id) || playerPaths[id] != currentPath {
                players[id]?.pause(); loopers[id]?.disableLooping(); loopers[id] = nil; players[id] = nil; playerPaths[id] = nil
            }
        }
        for candidate in videos where keep.contains(candidate.id) && players[candidate.id] == nil {
            let path = candidate.playbackPath ?? candidate.mediaPath
            guard let url = Self.mediaURL(path) else { continue }
            playerPaths[candidate.id] = path
            let item = AVPlayerItem(url: url); item.preferredForwardBufferDuration = candidate.id == video.id ? 3 : 1
            let player = AVQueuePlayer(); player.isMuted = isMuted; player.automaticallyWaitsToMinimizeStalling = true
            loopers[candidate.id] = AVPlayerLooper(player: player, templateItem: item); players[candidate.id] = player
        }
        for (id, player) in players where id != video.id { player.pause() }
        if activeId != video.id { detachObserver(); progress = 0; isPaused = false; playbackError = nil }
        activeId = video.id
        guard let player = players[video.id] else { playbackError = "Couldn't open this video."; return }
        if observedPlayer !== player {
            detachObserver()
            playbackError = nil; isBuffering = false
            if let resumeTime, resumeTime.seconds.isFinite && resumeTime.seconds > 0 { pendingSeek = resumeTime }
            observedPlayer = player
            let observation = observationId
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.15, preferredTimescale: 600), queue: .main) { [weak self] time in
                Task { @MainActor [weak self] in
                    guard let self, self.observationId == observation, let duration = self.observedPlayer?.currentItem?.duration.seconds, duration.isFinite, duration > 0 else { return }
                    self.progress = max(0, min(1, time.seconds / duration))
                }
            }
            currentItemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
                let item = player.currentItem
                Task { @MainActor [weak self] in
                    guard let self, self.observationId == observation, self.observedPlayer?.currentItem === item else { return }
                    self.observeStatus(of: item, observation: observation)
                }
            }
            statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
                let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                Task { @MainActor [weak self] in
                    guard let self, self.observationId == observation else { return }
                    self.isBuffering = waiting
                }
            }
        }
        if !isPaused { player.play() }
    }
    private func observeStatus(of item: AVPlayerItem?, observation: UUID) {
        itemStatusObservation = item?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            let message = status == .failed ? (item.error?.localizedDescription ?? "This video couldn't load.") : nil
            Task { @MainActor [weak self] in
                guard let self, self.observationId == observation, self.observedPlayer?.currentItem === item else { return }
                if let message { self.playbackError = message; self.isBuffering = false }
                if status == .readyToPlay, let position = self.pendingSeek {
                    self.pendingSeek = nil
                    self.observedPlayer?.seek(to: position, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
        }
    }
    func retry(_ video: Video, in videos: [Video]) {
        detachObserver(); players[video.id]?.pause(); loopers[video.id]?.disableLooping(); loopers[video.id] = nil; players[video.id] = nil
        activeId = nil; activate(video, in: videos)
    }
    func togglePause() { isPaused.toggle(); if isPaused { players[activeId ?? UUID()]?.pause() } else { players[activeId ?? UUID()]?.play() }; Haptics.selection() }
    func toggleMute() { isMuted.toggle(); for player in players.values { player.isMuted = isMuted }; Haptics.selection() }
    func suspend() { for player in players.values { player.pause() } }
    func resume() { if !isPaused, let activeId { players[activeId]?.play() } }
    func stop() { suspend(); detachObserver(); for looper in loopers.values { looper.disableLooping() }; loopers = [:]; players = [:]; playerPaths = [:]; activeId = nil; isBuffering = false }
    private func detachObserver() { observationId = UUID(); pendingSeek = nil; if let timeObserver { observedPlayer?.removeTimeObserver(timeObserver) }; timeObserver = nil; observedPlayer = nil; statusObservation = nil; currentItemObservation = nil; itemStatusObservation = nil }
    static func mediaURL(_ path: String) -> URL? {
        if path.hasPrefix("https://") || path.hasPrefix("file://") { return URL(string: path) }
        return Bundle.main.url(forResource: path, withExtension: nil)
    }
}

private final class PlayerSurface: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
struct PlayerView: UIViewRepresentable {
    let player: AVPlayer?
    func makeUIView(context: Context) -> UIView {
        let view = PlayerSurface(); view.backgroundColor = .black; view.playerLayer.videoGravity = .resizeAspectFill; view.playerLayer.player = player; return view
    }
    func updateUIView(_ uiView: UIView, context: Context) { (uiView as? PlayerSurface)?.playerLayer.player = player }
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) { (uiView as? PlayerSurface)?.playerLayer.player = nil }
}
