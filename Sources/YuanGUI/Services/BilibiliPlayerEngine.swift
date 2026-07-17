import AVFoundation
import Foundation

private struct BilibiliPlaybackTimeoutError: LocalizedError {
    var errorDescription: String? { "Bilibili 音频线路连接超时" }
}

@MainActor
final class BilibiliPlayerEngine: MusicPlaybackControlling {
    private(set) var player = AVPlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var candidateURLs: [URL] = []
    private var candidateIndex = 0
    private var requestHeaders: [String: String] = [:]
    private var requestedPosition: TimeInterval = 0
    private var shouldAutoplay = true
    private var loadWatchdog: Task<Void, Never>?
    var onStateChange: ((MusicPlaybackState) -> Void)?
    var onProgress: ((TimeInterval, TimeInterval) -> Void)?
    var onFinished: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    var hasLoadedItem: Bool { player.currentItem != nil }

    init() {
        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                let state: MusicPlaybackState
                switch player.timeControlStatus {
                case .playing:
                    state = .playing
                    self?.loadWatchdog?.cancel()
                    self?.loadWatchdog = nil
                case .waitingToPlayAtSpecifiedRate: state = .loading
                case .paused: state = player.currentItem == nil ? .stopped : .paused
                @unknown default: state = .paused
                }
                self?.onStateChange?(state)
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let duration = self.player.currentItem?.duration.seconds ?? 0
                self.onProgress?(time.seconds.isFinite ? time.seconds : 0, duration.isFinite ? duration : 0)
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor [weak self] in
                guard note.object as? AVPlayerItem === self?.player.currentItem else { return }
                self?.onFinished?()
            }
        }
        stalledObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.playbackStalledNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self, note.object as? AVPlayerItem === self.player.currentItem else { return }
                self.tryNextCandidate(after: URLError(.networkConnectionLost))
            }
        }
    }

    func load(urls: [URL], headers: [String: String], position: TimeInterval = 0, autoplay: Bool = true) {
        candidateURLs = urls
        candidateIndex = 0
        requestHeaders = headers
        requestedPosition = position
        shouldAutoplay = autoplay
        loadCurrentCandidate()
    }

    private func loadCurrentCandidate() {
        guard candidateURLs.indices.contains(candidateIndex) else {
            onFailure?(URLError(.cannotLoadFromNetwork))
            return
        }
        onStateChange?(.loading)
        let url = candidateURLs[candidateIndex]
        let asset = AVURLAsset(
            url: url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": requestHeaders]
        )
        let item = AVPlayerItem(asset: asset)
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let error = item.error ?? URLError(.cannotLoadFromNetwork)
            Task { @MainActor [weak self] in self?.tryNextCandidate(after: error) }
        }
        player.replaceCurrentItem(with: item)
        if requestedPosition > 0 { player.seek(to: CMTime(seconds: requestedPosition, preferredTimescale: 600)) }
        if shouldAutoplay { player.play() }
        startLoadWatchdog(for: candidateIndex)
    }

    private func startLoadWatchdog(for index: Int) {
        loadWatchdog?.cancel()
        loadWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.candidateIndex == index,
                  self.player.timeControlStatus != .playing else { return }
            self.tryNextCandidate(after: BilibiliPlaybackTimeoutError())
        }
    }

    private func tryNextCandidate(after error: Error) {
        loadWatchdog?.cancel()
        loadWatchdog = nil
        guard candidateIndex + 1 < candidateURLs.count else {
            onFailure?(error)
            return
        }
        let current = player.currentTime().seconds
        if current.isFinite, current > 0 { requestedPosition = current }
        candidateIndex += 1
        loadCurrentCandidate()
    }

    func playPause() { player.timeControlStatus == .playing ? player.pause() : player.play() }
    func pause() { player.pause() }
    func previous() { }
    func next() { }
    func seek(to position: TimeInterval) { player.seek(to: CMTime(seconds: max(0, position), preferredTimescale: 600)) }
    func setVolume(_ volume: Double) { player.volume = Float(min(max(volume, 0), 1)) }

    func stop() {
        loadWatchdog?.cancel()
        loadWatchdog = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        candidateURLs.removeAll()
    }

    deinit {
        loadWatchdog?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let stalledObserver { NotificationCenter.default.removeObserver(stalledObserver) }
    }
}
