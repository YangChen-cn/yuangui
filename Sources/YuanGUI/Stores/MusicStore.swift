import AppKit
import Combine
import Foundation

@MainActor
final class MusicPlaybackProgress: ObservableObject {
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    func setPosition(_ position: TimeInterval) {
        guard self.position != position else { return }
        self.position = position
    }

    func setDuration(_ duration: TimeInterval) {
        guard self.duration != duration else { return }
        self.duration = duration
    }

    func reset(position: TimeInterval = 0, duration: TimeInterval = 0) {
        setPosition(position)
        setDuration(duration)
    }
}

@MainActor
final class MusicStore: ObservableObject {
    @Published private(set) var browsingSource: MusicSource
    @Published private(set) var activePlaybackSource: MusicSource? = nil
    @Published private(set) var playbackState: MusicPlaybackState = .stopped
    @Published private(set) var currentTrack: MusicTrack?
    @Published private(set) var volume: Double
    @Published private(set) var playlist: [MusicTrack] = []
    @Published private(set) var playMode: MusicPlayMode = .sequential
    @Published private(set) var favoriteTrackIDs: Set<String> = []
    @Published private(set) var savedPlaylists: [SavedMusicPlaylist] = []
    @Published private(set) var lyrics: LyricsDocument?
    @Published private(set) var currentLyric: TimedLyricLine?
    @Published private(set) var nextLyric: TimedLyricLine?
    @Published private(set) var currentLyricIndex: Int?
    @Published private(set) var isLoadingLyrics = false
    @Published private(set) var appleMusicRunning = false
    @Published private(set) var isImporting = false
    @Published private(set) var bilibiliImportMessage: String?
    @Published var importText = ""
    @Published var errorMessage: String?
    @Published private(set) var lyricsVisible: Bool
    @Published private(set) var lightSingAlongEnabled: Bool
    @Published private(set) var lyricsPanelLocked: Bool
    @Published private(set) var lyricsFontSize: Double
    @Published private(set) var lyricsFontStyle: LyricsFontStyle
    @Published private(set) var lyricsColor: NSColor
    @Published private(set) var lyricsShadowEnabled: Bool
    @Published private(set) var lyricsBackgroundVisible: Bool
    @Published private(set) var lyricOffsets: [String: TimeInterval] = [:]
    @Published private(set) var isSearchingLyrics = false
    @Published private(set) var lyricsSearchMessage: String?
    @Published private(set) var bilibiliAccount: BilibiliAccount?
    @Published private(set) var bilibiliLoginPhase: BilibiliLoginPhase = .loggedOut
    @Published private(set) var bilibiliQRCodeURL: String?
    @Published private(set) var bilibiliFavoriteFolders: [BilibiliFavoriteFolder] = []
    @Published private(set) var isLoadingBilibiliFavoriteFolders = false
    @Published private(set) var isImportingBilibiliFavoriteFolder = false
    @Published private(set) var bilibiliFavoriteImportCompleted = 0
    @Published private(set) var bilibiliFavoriteImportTotal = 0
    @Published private(set) var bilibiliFavoriteMessage: String?
    @Published var isMiniPlayerPresented = false

    let playbackProgress = MusicPlaybackProgress()
    private let appleMusic = AppleMusicController()
    private let bilibili = BilibiliClient()
    private let bilibiliAccountService = BilibiliAccountService()
    private let bilibiliFavoritesService = BilibiliFavoritesService()
    private let bilibiliPlayer = BilibiliPlayerEngine()
    private let lyricsService = LyricsService()
    private let library = MusicLibraryActor()
    private let defaults: UserDefaults
    private var syncTask: Task<Void, Never>?
    private var appleClockTask: Task<Void, Never>?
    private var appleRefreshTask: Task<Void, Never>?
    private var appleArtworkTask: Task<Void, Never>?
    private var bilibiliImportResultTask: Task<Void, Never>?
    private var lyricLoadTask: Task<Void, Never>?
    private var lyricsSearchTask: Task<Void, Never>?
    private var bilibiliLoadTask: Task<Void, Never>?
    private var bilibiliLoginTask: Task<Void, Never>?
    private var bilibiliFavoriteTask: Task<Void, Never>?
    private var lyricsByTrackID: [String: LyricsDocument] = [:]
    private var currentTrackID: String?
    private var lastSavedSecond = -1
    private var lastBilibiliPosition: TimeInterval = 0
    private var bilibiliRefreshAttempted = false
    private var bilibiliVolume: Double
    private var lastImportedTrackID: String?
    private var persistenceRevision: UInt64 = 0
    private var lyricLoadRevision: UInt64 = 0
    private var lastAppleClockTime: TimeInterval?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.browsingSource = MusicSource(rawValue: defaults.string(forKey: "musicSource") ?? "") ?? .appleMusic
        let savedBilibiliVolume = defaults.object(forKey: "bilibiliMusicVolume") as? Double ?? 0.8
        self.volume = savedBilibiliVolume
        self.bilibiliVolume = savedBilibiliVolume
        self.lyricsVisible = defaults.bool(forKey: "musicLyricsVisible")
        self.lightSingAlongEnabled = defaults.object(forKey: "musicLightSingAlong") == nil ? true : defaults.bool(forKey: "musicLightSingAlong")
        self.lyricsPanelLocked = defaults.bool(forKey: "musicLyricsPanelLocked")
        self.lyricsFontSize = min(max(defaults.object(forKey: "musicLyricsFontSize") as? Double ?? 21, 14), 42)
        self.lyricsFontStyle = LyricsFontStyle(rawValue: defaults.string(forKey: "musicLyricsFontStyle") ?? "") ?? .rounded
        self.lyricsColor = Self.decodeColor(defaults.string(forKey: "musicLyricsColor")) ?? .white
        self.lyricsShadowEnabled = defaults.object(forKey: "musicLyricsShadowEnabled") == nil
            ? true
            : defaults.bool(forKey: "musicLyricsShadowEnabled")
        self.lyricsBackgroundVisible = defaults.bool(forKey: "musicLyricsBackgroundVisible")
        bilibiliPlayer.setVolume(volume)
        bilibiliPlayer.onStateChange = { [weak self] state in
            guard let self, self.activePlaybackSource == .bilibili else { return }
            if self.playbackState != state { self.playbackState = state }
        }
        bilibiliPlayer.onProgress = { [weak self] position, duration in
            guard let self, self.activePlaybackSource == .bilibili else { return }
            self.playbackProgress.setPosition(position)
            self.lastBilibiliPosition = position
            if duration > 0 { self.playbackProgress.setDuration(duration) }
            self.updateLyric()
            self.persistProgressIfNeeded()
        }
        bilibiliPlayer.onFinished = { [weak self] in self?.handleTrackFinished() }
        bilibiliPlayer.onFailure = { [weak self] error in self?.handleBilibiliFailure(error) }
        refreshBilibiliAccount()
        syncTask = Task { [weak self] in
            await self?.restoreLibrary()
            await self?.runSyncLoop()
        }
        appleClockTask = Task { [weak self] in
            await self?.runAppleClock()
        }
    }

    var progress: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }
    var position: TimeInterval { playbackProgress.position }
    var duration: TimeInterval { playbackProgress.duration }
    var source: MusicSource { browsingSource }
    var playbackSource: MusicSource { activePlaybackSource ?? currentTrack?.source ?? browsingSource }
    var isPlaying: Bool { playbackState.isPlaying }
    var canControl: Bool {
        if let activePlaybackSource {
            return activePlaybackSource == .appleMusic ? true : currentTrack != nil
        }
        return browsingSource == .appleMusic ? true : currentTrack != nil || !playlist.isEmpty
    }
    var currentLyricOffset: TimeInterval { currentTrack.flatMap { lyricOffsets[$0.id] } ?? 0 }

    func setSource(_ newSource: MusicSource) {
        guard newSource != browsingSource else { return }
        browsingSource = newSource
        defaults.set(newSource.rawValue, forKey: "musicSource")
        if newSource == .bilibili, activePlaybackSource == nil, currentTrack == nil {
            restoreBilibiliSelection()
        }
    }

    @discardableResult
    private func activatePlaybackSource(_ newSource: MusicSource) -> Bool {
        guard activePlaybackSource != newSource else { return false }
        switch newSource {
        case .appleMusic:
            if activePlaybackSource == .bilibili { lastBilibiliPosition = position }
            bilibiliLoadTask?.cancel()
            bilibiliLoadTask = nil
            bilibiliPlayer.pause()
        case .bilibili:
            Task { [appleMusic] in await appleMusic.pause() }
            if volume != bilibiliVolume { volume = bilibiliVolume }
            bilibiliPlayer.setVolume(bilibiliVolume)
        }
        activePlaybackSource = newSource
        return true
    }

    private func clearTransientPlaybackState() {
        currentTrack = nil
        playbackProgress.reset()
        playbackState = .stopped
        lyrics = nil
        currentLyric = nil
        nextLyric = nil
        currentLyricIndex = nil
        errorMessage = nil
        lyricsSearchMessage = nil
        isSearchingLyrics = false
        cancelLyricLoad()
        lyricsSearchTask?.cancel()
        lyricsSearchTask = nil
    }

    func connectAppleMusic(autoplay: Bool = false) {
        setSource(.appleMusic)
        if activatePlaybackSource(.appleMusic) { clearTransientPlaybackState() }
        if !appleMusicRunning {
            openAppleMusic()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.finishAppleMusicConnection(autoplay: autoplay)
            }
        } else {
            finishAppleMusicConnection(autoplay: autoplay)
        }
    }

    private func finishAppleMusicConnection(autoplay: Bool) {
        Task { [weak self] in
            guard let self, activePlaybackSource == .appleMusic else { return }
            await refreshAppleMusic()
            guard activePlaybackSource == .appleMusic else { return }
            if autoplay, appleMusicRunning, !playbackState.isPlaying {
                playbackState = .playing
                lastAppleClockTime = Date.timeIntervalSinceReferenceDate
                await appleMusic.playPause()
                scheduleAppleRefresh()
            }
        }
    }

    func openAppleMusic() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Music.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    func playPause() {
        errorMessage = nil
        guard let activePlaybackSource else {
            if currentTrack?.source == .bilibili || browsingSource == .bilibili {
                if let currentTrack, currentTrack.source == .bilibili { play(currentTrack, at: position) }
                else if let first = playlist.first { play(first) }
            } else {
                connectAppleMusic(autoplay: true)
            }
            return
        }
        switch activePlaybackSource {
        case .appleMusic:
            guard appleMusicRunning else { connectAppleMusic(autoplay: true); return }
            playbackState = playbackState.isPlaying ? .paused : .playing
            lastAppleClockTime = Date.timeIntervalSinceReferenceDate
            Task { [weak self, appleMusic] in
                await appleMusic.playPause()
                self?.scheduleAppleRefresh()
            }
        case .bilibili:
            if let currentTrack, !bilibiliPlayer.hasLoadedItem {
                play(currentTrack, at: position)
            } else if currentTrack == nil, let first = playlist.first {
                play(first)
            } else {
                bilibiliPlayer.playPause()
            }
        }
    }

    func previous() { move(by: -1) }
    func next() { move(by: 1) }

    func seek(to newPosition: TimeInterval) {
        let lowerBounded = max(newPosition, 0)
        let target = duration > 0 ? min(lowerBounded, duration) : lowerBounded
        playbackProgress.setPosition(target)
        if playbackSource == .bilibili { lastBilibiliPosition = target }
        if playbackSource == .appleMusic {
            lastAppleClockTime = Date.timeIntervalSinceReferenceDate
            Task { [appleMusic] in await appleMusic.seek(to: target) }
        } else {
            bilibiliPlayer.seek(to: target)
        }
        updateLyric()
    }

    func seek(toLyric line: TimedLyricLine) {
        seek(to: Self.lyricSeekPosition(for: line, offset: currentLyricOffset, duration: duration))
    }

    nonisolated static func lyricSeekPosition(
        for line: TimedLyricLine,
        offset: TimeInterval,
        duration: TimeInterval
    ) -> TimeInterval {
        let target = max(0, line.time + offset)
        return duration > 0 ? min(target, duration) : target
    }

    func setVolume(_ newValue: Double) {
        volume = min(max(newValue, 0), 1)
        if playbackSource == .appleMusic { Task { [appleMusic, volume] in await appleMusic.setVolume(volume) } }
        else {
            bilibiliVolume = volume
            bilibiliPlayer.setVolume(volume)
            defaults.set(volume, forKey: "bilibiliMusicVolume")
        }
    }

    func setPlayMode(_ mode: MusicPlayMode) { playMode = mode; persistLibrary() }

    func importBilibili() {
        let input = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isImporting = true
        errorMessage = nil
        dismissBilibiliImportResult()
        Task { [weak self] in
            guard let self else { return }
            do {
                let tracks = try await bilibili.resolveTracks(from: input)
                var added: [MusicTrack] = []
                for track in tracks where !playlist.contains(where: { $0.id == track.id }) {
                    playlist.append(track); added.append(track)
                }
                importText = ""
                setSource(.bilibili)
                persistLibrary()
                let importedTrackID = (added.first ?? tracks.first)?.id
                let message = added.isEmpty
                    ? "歌曲已在资料库中"
                    : "已加入 \(added.count) 首歌曲"
                showBilibiliImportResult(message, trackID: importedTrackID)
            } catch { errorMessage = error.localizedDescription }
            isImporting = false
        }
    }

    func playLastBilibiliImport() {
        guard let lastImportedTrackID,
              let track = playlist.first(where: { $0.id == lastImportedTrackID }) else {
            dismissBilibiliImportResult()
            return
        }
        dismissBilibiliImportResult()
        play(track)
    }

    func dismissBilibiliImportResult() {
        bilibiliImportResultTask?.cancel()
        bilibiliImportResultTask = nil
        bilibiliImportMessage = nil
        lastImportedTrackID = nil
    }

    private func showBilibiliImportResult(_ message: String, trackID: String?) {
        bilibiliImportResultTask?.cancel()
        bilibiliImportMessage = message
        lastImportedTrackID = trackID
        bilibiliImportResultTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, bilibiliImportMessage == message, lastImportedTrackID == trackID else { return }
            dismissBilibiliImportResult()
        }
    }

    func loadBilibiliFavoriteFolders() {
        guard let account = bilibiliAccount else {
            bilibiliFavoriteMessage = "请先登录哔哩哔哩账号"
            return
        }
        bilibiliFavoriteTask?.cancel()
        isLoadingBilibiliFavoriteFolders = true
        bilibiliFavoriteMessage = nil
        bilibiliFavoriteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let folders = try await bilibiliFavoritesService.folders(for: account.mid)
                guard !Task.isCancelled else { return }
                bilibiliFavoriteFolders = folders
                if folders.isEmpty { bilibiliFavoriteMessage = "这个账号没有可导入的视频收藏夹" }
            } catch is CancellationError {
                return
            } catch {
                bilibiliFavoriteMessage = error.localizedDescription
            }
            isLoadingBilibiliFavoriteFolders = false
            bilibiliFavoriteTask = nil
        }
    }

    func importBilibiliFavoriteFolder(_ folder: BilibiliFavoriteFolder) {
        guard bilibiliAccount != nil, !isImportingBilibiliFavoriteFolder else { return }
        bilibiliFavoriteTask?.cancel()
        isLoadingBilibiliFavoriteFolders = false
        isImportingBilibiliFavoriteFolder = true
        bilibiliFavoriteImportCompleted = 0
        bilibiliFavoriteImportTotal = max(folder.mediaCount, 0)
        bilibiliFavoriteMessage = nil
        bilibiliFavoriteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let bvids = try await bilibiliFavoritesService.videoBVIDs(in: folder)
                guard !bvids.isEmpty else {
                    bilibiliFavoriteMessage = "“\(folder.title)”没有可导入的公开视频"
                    isImportingBilibiliFavoriteFolder = false
                    bilibiliFavoriteTask = nil
                    return
                }
                bilibiliFavoriteImportTotal = bvids.count
                var resolved: [(Int, [MusicTrack])] = []
                var failedCount = 0
                let batchSize = 4
                let client = bilibili
                for start in stride(from: 0, to: bvids.count, by: batchSize) {
                    try Task.checkCancellation()
                    let end = min(start + batchSize, bvids.count)
                    let batch = Array(bvids[start..<end].enumerated()).map { (start + $0.offset, $0.element) }
                    let batchResults = await withTaskGroup(of: (Int, [MusicTrack]?).self) { group in
                        for (index, bvid) in batch {
                            group.addTask { [client] in
                                do { return (index, try await client.resolveTracks(from: bvid)) }
                                catch { return (index, nil) }
                            }
                        }
                        var values: [(Int, [MusicTrack]?)] = []
                        for await value in group { values.append(value) }
                        return values
                    }
                    for (index, tracks) in batchResults {
                        if let tracks { resolved.append((index, tracks)) }
                        else { failedCount += 1 }
                        bilibiliFavoriteImportCompleted += 1
                    }
                }
                guard !Task.isCancelled else { return }
                let tracks = resolved.sorted { $0.0 < $1.0 }.flatMap(\.1)
                let existingIDs = Set(playlist.map(\.id))
                let added = tracks.filter { !existingIDs.contains($0.id) }
                playlist.append(contentsOf: added)
                updateLocalPlaylist(named: folder.title, with: tracks)
                setSource(.bilibili)
                persistLibrary()
                let duplicateCount = tracks.count - added.count
                var details = "已从“\(folder.title)”导入 \(added.count) 首"
                if duplicateCount > 0 { details += "，跳过 \(duplicateCount) 首重复歌曲" }
                if failedCount > 0 { details += "，\(failedCount) 个视频解析失败" }
                bilibiliFavoriteMessage = details
            } catch is CancellationError {
                return
            } catch {
                bilibiliFavoriteMessage = error.localizedDescription
            }
            isImportingBilibiliFavoriteFolder = false
            bilibiliFavoriteTask = nil
        }
    }

    func cancelBilibiliFavoriteOperation() {
        bilibiliFavoriteTask?.cancel()
        bilibiliFavoriteTask = nil
        isLoadingBilibiliFavoriteFolders = false
        isImportingBilibiliFavoriteFolder = false
    }

    private func updateLocalPlaylist(named name: String, with tracks: [MusicTrack]) {
        guard !tracks.isEmpty else { return }
        if let index = savedPlaylists.firstIndex(where: { $0.name == name }) {
            var existing = Set(savedPlaylists[index].trackIDs)
            savedPlaylists[index].trackIDs.append(contentsOf: tracks.map(\.id).filter { existing.insert($0).inserted })
        } else {
            var seen = Set<String>()
            savedPlaylists.append(SavedMusicPlaylist(
                name: name,
                trackIDs: tracks.map(\.id).filter { seen.insert($0).inserted }
            ))
        }
    }

    func refreshBilibiliAccount() {
        Task { [weak self] in
            guard let self else { return }
            do {
                bilibiliAccount = try await bilibiliAccountService.currentAccount()
                bilibiliLoginPhase = bilibiliAccount == nil ? .loggedOut : .loggedIn
            } catch {
                bilibiliLoginPhase = .failed(error.localizedDescription)
            }
        }
    }

    func startBilibiliLogin() {
        bilibiliLoginTask?.cancel()
        bilibiliLoginPhase = .requestingQRCode
        bilibiliQRCodeURL = nil
        bilibiliLoginTask = Task { [weak self] in
            guard let self else { return }
            do {
                let code = try await bilibiliAccountService.generateQRCode()
                guard !Task.isCancelled else { return }
                bilibiliQRCodeURL = code.url
                bilibiliLoginPhase = .waitingForScan
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(2))
                    switch try await bilibiliAccountService.pollQRCode(key: code.key) {
                    case .waitingForScan:
                        bilibiliLoginPhase = .waitingForScan
                    case .waitingForConfirmation:
                        bilibiliLoginPhase = .waitingForConfirmation
                    case .expired:
                        bilibiliLoginPhase = .expired
                        bilibiliQRCodeURL = nil
                        bilibiliLoginTask = nil
                        return
                    case .succeeded:
                        guard let account = try await bilibiliAccountService.currentAccount() else {
                            throw BilibiliAccountError.api("登录凭据未生效")
                        }
                        bilibiliAccount = account
                        bilibiliLoginPhase = .loggedIn
                        bilibiliQRCodeURL = nil
                        bilibiliLoginTask = nil
                        await refreshCurrentBilibiliSubtitleAfterLogin()
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                bilibiliLoginPhase = .failed(error.localizedDescription)
                bilibiliQRCodeURL = nil
                bilibiliLoginTask = nil
            }
        }
    }

    func cancelBilibiliLogin() {
        bilibiliLoginTask?.cancel()
        bilibiliLoginTask = nil
        bilibiliQRCodeURL = nil
        if bilibiliAccount == nil { bilibiliLoginPhase = .loggedOut }
    }

    func logoutBilibili() {
        bilibiliLoginTask?.cancel()
        bilibiliLoginTask = nil
        Task { [weak self] in
            guard let self else { return }
            await bilibiliAccountService.logout()
            bilibiliAccount = nil
            bilibiliQRCodeURL = nil
            bilibiliLoginPhase = .loggedOut
            bilibiliFavoriteFolders = []
            bilibiliFavoriteMessage = nil
        }
    }

    func play(_ track: MusicTrack, at savedPosition: TimeInterval = 0) {
        guard track.source == .bilibili else { return }
        activatePlaybackSource(.bilibili)
        currentTrack = track
        currentTrackID = track.id
        lastBilibiliPosition = savedPosition
        playbackProgress.reset(position: savedPosition, duration: track.duration)
        playbackState = .loading
        errorMessage = nil
        bilibiliRefreshAttempted = false
        loadLyrics(for: track)
        loadBilibiliTrack(track, position: savedPosition)
    }

    private func loadBilibiliTrack(_ track: MusicTrack, position savedPosition: TimeInterval) {
        bilibiliLoadTask?.cancel()
        bilibiliLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let location = try await bilibili.audioLocation(for: track)
                let headers = await bilibili.playbackHeaders()
                guard !Task.isCancelled,
                      activePlaybackSource == .bilibili,
                      currentTrack?.id == track.id else { return }
                bilibiliPlayer.load(urls: location.candidates, headers: headers, position: savedPosition)
                persistLibrary()
            } catch {
                guard !Task.isCancelled, activePlaybackSource == .bilibili else { return }
                playbackState = .failed(error.localizedDescription)
                errorMessage = error.localizedDescription
            }
            bilibiliLoadTask = nil
        }
    }

    func remove(_ track: MusicTrack) {
        let wasCurrent = currentTrack?.id == track.id
        playlist.removeAll { $0.id == track.id }
        favoriteTrackIDs.remove(track.id)
        removeCachedLyrics(for: track)
        for index in savedPlaylists.indices { savedPlaylists[index].trackIDs.removeAll { $0 == track.id } }
        if wasCurrent {
            bilibiliPlayer.stop(); currentTrack = nil; currentTrackID = nil; playbackState = .stopped
            lastBilibiliPosition = 0
            if activePlaybackSource == .bilibili { activePlaybackSource = nil }
            playbackProgress.reset(); cancelLyricLoad()
            lyrics = nil; currentLyric = nil; nextLyric = nil; currentLyricIndex = nil
        }
        persistLibrary()
    }

    func clearPlaylist() {
        for track in playlist { removeCachedLyrics(for: track) }
        bilibiliPlayer.stop(); playlist.removeAll(); favoriteTrackIDs.removeAll(); savedPlaylists.removeAll()
        currentTrackID = nil
        lastBilibiliPosition = 0
        if activePlaybackSource == .bilibili || currentTrack?.source == .bilibili {
            activePlaybackSource = nil
            currentTrack = nil; playbackState = .stopped
            playbackProgress.reset(); cancelLyricLoad()
            lyrics = nil; currentLyric = nil; nextLyric = nil; currentLyricIndex = nil
        }
        persistLibrary()
    }

    func isFavorite(_ track: MusicTrack) -> Bool { favoriteTrackIDs.contains(track.id) }

    func toggleFavorite(_ track: MusicTrack) {
        if favoriteTrackIDs.contains(track.id) { favoriteTrackIDs.remove(track.id) }
        else { favoriteTrackIDs.insert(track.id) }
        persistLibrary()
    }

    @discardableResult
    func createPlaylist(named rawName: String) -> SavedMusicPlaylist? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let playlist = SavedMusicPlaylist(name: name)
        savedPlaylists.append(playlist)
        persistLibrary()
        return playlist
    }

    func deletePlaylist(_ savedPlaylist: SavedMusicPlaylist) {
        savedPlaylists.removeAll { $0.id == savedPlaylist.id }
        persistLibrary()
    }

    func add(_ track: MusicTrack, to savedPlaylist: SavedMusicPlaylist) {
        guard let index = savedPlaylists.firstIndex(where: { $0.id == savedPlaylist.id }),
              !savedPlaylists[index].trackIDs.contains(track.id) else { return }
        savedPlaylists[index].trackIDs.append(track.id)
        persistLibrary()
    }

    func remove(_ track: MusicTrack, from savedPlaylist: SavedMusicPlaylist) {
        guard let index = savedPlaylists.firstIndex(where: { $0.id == savedPlaylist.id }) else { return }
        savedPlaylists[index].trackIDs.removeAll { $0 == track.id }
        persistLibrary()
    }

    func tracks(in savedPlaylist: SavedMusicPlaylist) -> [MusicTrack] {
        let byID = Dictionary(uniqueKeysWithValues: playlist.map { ($0.id, $0) })
        return savedPlaylist.trackIDs.compactMap { byID[$0] }
    }

    var favoriteTracks: [MusicTrack] { playlist.filter { favoriteTrackIDs.contains($0.id) } }

    func toggleLyricsVisible() {
        lyricsVisible.toggle()
        defaults.set(lyricsVisible, forKey: "musicLyricsVisible")
        NotificationCenter.default.post(name: .musicLyricsVisibilityChanged, object: nil)
    }

    func setLightSingAlongEnabled(_ enabled: Bool) {
        lightSingAlongEnabled = enabled
        defaults.set(enabled, forKey: "musicLightSingAlong")
    }

    func setLyricsPanelLocked(_ locked: Bool) {
        lyricsPanelLocked = locked
        defaults.set(locked, forKey: "musicLyricsPanelLocked")
        NotificationCenter.default.post(name: .musicLyricsLockChanged, object: nil)
    }

    func setLyricsFontSize(_ size: Double) {
        lyricsFontSize = min(max(size, 14), 42)
        defaults.set(lyricsFontSize, forKey: "musicLyricsFontSize")
    }

    func setLyricsFontStyle(_ style: LyricsFontStyle) {
        lyricsFontStyle = style
        defaults.set(style.rawValue, forKey: "musicLyricsFontStyle")
    }

    func setLyricsColor(_ color: NSColor) {
        guard let color = color.usingColorSpace(.sRGB) else { return }
        lyricsColor = color
        defaults.set(Self.encodeColor(color), forKey: "musicLyricsColor")
    }

    func setLyricsShadowEnabled(_ enabled: Bool) {
        lyricsShadowEnabled = enabled
        defaults.set(enabled, forKey: "musicLyricsShadowEnabled")
    }

    func setLyricsBackgroundVisible(_ visible: Bool) {
        lyricsBackgroundVisible = visible
        defaults.set(visible, forKey: "musicLyricsBackgroundVisible")
    }

    func setLyricOffset(_ offset: TimeInterval) {
        guard let trackID = currentTrack?.id else { return }
        let clamped = min(max(offset, -30), 30)
        if abs(clamped) < 0.001 { lyricOffsets.removeValue(forKey: trackID) }
        else { lyricOffsets[trackID] = clamped }
        updateLyric()
        persistLibrary()
    }

    func searchLyrics(title rawTitle: String, artist rawArtist: String) {
        guard let track = currentTrack else { return }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = rawArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            lyricsSearchMessage = "请填写歌曲名"
            return
        }
        isSearchingLyrics = true
        lyricsSearchMessage = nil
        cancelLyricLoad()
        lyricsSearchTask?.cancel()
        lyricsSearchTask = Task { [weak self] in
            guard let self else { return }
            let found: LyricsDocument?
            do {
                found = try await lyricsService.search(title: title, artist: artist, duration: track.duration)
            } catch is CancellationError {
                return
            } catch {
                guard currentTrack?.id == track.id else { return }
                lyricsSearchMessage = error.localizedDescription
                isSearchingLyrics = false
                lyricsSearchTask = nil
                return
            }
            guard !Task.isCancelled, currentTrack?.id == track.id else { return }
            if let found {
                lyrics = found
                cacheLyrics(found, for: track)
                updateMetadata(for: track.id, title: title, artist: artist)
                updateLyric()
                persistLibrary()
                lyricsSearchMessage = "已匹配歌词，并更新为“\(title) — \(artist.isEmpty ? "未知歌手" : artist)”"
            } else {
                lyricsSearchMessage = "没有找到可信度足够的同步歌词，已保留原有歌词"
            }
            isSearchingLyrics = false
            lyricsSearchTask = nil
        }
    }

    @discardableResult
    func updateCurrentTrackMetadata(title rawTitle: String, artist rawArtist: String) -> Bool {
        guard let track = currentTrack else { return false }
        let enteredTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredArtist = rawArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = enteredTitle.isEmpty ? track.title : enteredTitle
        let artist = enteredArtist.isEmpty ? track.artist : enteredArtist
        guard !title.isEmpty, !artist.isEmpty else {
            lyricsSearchMessage = "歌曲名和歌手不能同时留空"
            return false
        }
        updateMetadata(for: track.id, title: title, artist: artist)
        lyricsSearchMessage = "已保存歌曲信息：“\(title) — \(artist)”；原有歌词保持不变"
        return true
    }

    private func updateMetadata(for trackID: String, title: String, artist: String) {
        let resolvedArtist = artist.isEmpty ? (currentTrack?.artist ?? "未知歌手") : artist
        if let index = playlist.firstIndex(where: { $0.id == trackID }) {
            playlist[index].title = title
            playlist[index].artist = resolvedArtist
            currentTrack = playlist[index]
            persistLibrary()
        } else if currentTrack?.id == trackID {
            currentTrack?.title = title
            currentTrack?.artist = resolvedArtist
        }
    }

    private static func encodeColor(_ color: NSColor) -> String {
        let color = color.usingColorSpace(.sRGB) ?? color
        return String(
            format: "#%02X%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255)),
            Int(round(color.alphaComponent * 255))
        )
    }

    private static func decodeColor(_ value: String?) -> NSColor? {
        guard let value else { return nil }
        let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6 || hex.count == 8, let raw = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        return NSColor(
            red: CGFloat((raw >> (hasAlpha ? 24 : 16)) & 0xFF) / 255,
            green: CGFloat((raw >> (hasAlpha ? 16 : 8)) & 0xFF) / 255,
            blue: CGFloat((raw >> (hasAlpha ? 8 : 0)) & 0xFF) / 255,
            alpha: hasAlpha ? CGFloat(raw & 0xFF) / 255 : 1
        )
    }

    func importLRC(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            errorMessage = "无法读取这个 LRC 文件"; return
        }
        cancelLyricLoad()
        let document = LyricsParser.parseLRC(text)
        lyrics = document
        if let track = currentTrack {
            cacheLyrics(document, for: track)
            persistLibrary()
        }
        updateLyric()
    }

    func showFullPlayer() {
        // A SwiftUI popover is hosted by a non-activating panel. Let it close before
        // asking the regular player window to become key, otherwise the panel can
        // reclaim focus at the end of the current mouse event.
        isMiniPlayerPresented = false
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .showYuanGUIMusic, object: nil)
        }
    }

    func shutdown() async {
        syncTask?.cancel(); appleClockTask?.cancel(); appleRefreshTask?.cancel(); appleArtworkTask?.cancel(); bilibiliImportResultTask?.cancel()
        lyricLoadTask?.cancel(); lyricsSearchTask?.cancel(); bilibiliLoadTask?.cancel(); bilibiliLoginTask?.cancel(); bilibiliFavoriteTask?.cancel(); bilibiliPlayer.stop()
        persistenceRevision &+= 1
        await library.saveNow(librarySnapshot(), revision: persistenceRevision)
    }

    private func refreshAppleMusic() async {
        let running = await appleMusic.isRunning()
        if appleMusicRunning != running { appleMusicRunning = running }
        guard appleMusicRunning else {
            if activePlaybackSource == .appleMusic { playbackState = .stopped }
            lastAppleClockTime = nil
            return
        }
        guard activePlaybackSource == .appleMusic else { return }
        do {
            let snapshot = try await appleMusic.requestSnapshot()
            guard activePlaybackSource == .appleMusic else { return }
            let changed = currentTrack?.id != snapshot.track?.id
            var publishedTrack = snapshot.track
            if publishedTrack?.id == currentTrack?.id, publishedTrack?.coverURL == nil {
                publishedTrack?.coverURL = currentTrack?.coverURL
            }
            if currentTrack != publishedTrack { currentTrack = publishedTrack }
            if playbackState != snapshot.state { playbackState = snapshot.state }
            playbackProgress.reset(position: snapshot.position, duration: snapshot.track?.duration ?? 0)
            lastAppleClockTime = Date.timeIntervalSinceReferenceDate
            if volume != snapshot.volume { volume = snapshot.volume }
            if changed, let track = publishedTrack {
                loadLyrics(for: track)
                loadAppleArtwork(for: track)
            }
            updateLyric()
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func runSyncLoop() async {
        while !Task.isCancelled {
            await refreshAppleMusic()
            do { try await Task.sleep(for: .milliseconds(2500)) } catch { return }
        }
    }

    private func runAppleClock() async {
        while !Task.isCancelled {
            let now = Date.timeIntervalSinceReferenceDate
            if activePlaybackSource == .appleMusic, playbackState.isPlaying {
                if let lastAppleClockTime {
                    let elapsed = min(max(now - lastAppleClockTime, 0), 1)
                    let advanced = duration > 0 ? min(position + elapsed, duration) : position + elapsed
                    playbackProgress.setPosition(advanced)
                    updateLyric()
                }
                lastAppleClockTime = now
            } else {
                lastAppleClockTime = nil
            }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        }
    }

    private func loadAppleArtwork(for track: MusicTrack) {
        appleArtworkTask?.cancel()
        appleArtworkTask = Task { [weak self, appleMusic] in
            let url = await appleMusic.artworkURL(for: track.id)
            guard !Task.isCancelled, let self, currentTrack?.id == track.id else { return }
            if currentTrack?.coverURL != url { currentTrack?.coverURL = url }
            appleArtworkTask = nil
        }
    }

    private func scheduleAppleRefresh() {
        appleRefreshTask?.cancel()
        appleRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            await self?.refreshAppleMusic()
        }
    }

    private func move(by delta: Int) {
        let controlSource = activePlaybackSource ?? currentTrack?.source ?? browsingSource
        if controlSource == .appleMusic {
            if activePlaybackSource == nil { connectAppleMusic() }
            Task { [weak self, appleMusic] in
                if delta < 0 { await appleMusic.previous() } else { await appleMusic.next() }
                self?.scheduleAppleRefresh()
            }
            return
        }
        guard !playlist.isEmpty else { return }
        if playMode == .shuffle {
            let choices = playlist.filter { $0.id != currentTrack?.id }
            if let track = (choices.isEmpty ? playlist : choices).randomElement() { play(track) }
            return
        }
        let current = playlist.firstIndex(where: { $0.id == currentTrack?.id }) ?? 0
        let target = current + delta
        if playlist.indices.contains(target) { play(playlist[target]) }
        else if playMode == .repeatAll { play(delta < 0 ? playlist.last! : playlist.first!) }
    }

    private func handleTrackFinished() {
        guard activePlaybackSource == .bilibili else { return }
        if playMode == .repeatOne, let currentTrack { play(currentTrack) }
        else { move(by: 1) }
    }

    private func handleBilibiliFailure(_ error: Error) {
        guard activePlaybackSource == .bilibili, let track = currentTrack else { return }
        if !bilibiliRefreshAttempted {
            bilibiliRefreshAttempted = true
            playbackState = .loading
            loadBilibiliTrack(track, position: position)
        } else {
            playbackState = .failed("播放地址已失效，刷新后仍无法播放")
            errorMessage = "播放地址已失效，刷新后仍无法播放：\(error.localizedDescription)"
        }
    }

    private func loadLyrics(for track: MusicTrack) {
        lyricsSearchTask?.cancel()
        lyricsSearchTask = nil
        cancelLyricLoad()
        let revision = lyricLoadRevision
        isSearchingLyrics = false
        lyricsSearchMessage = nil
        if track.source != .bilibili, let cached = cachedLyrics(for: track) {
            lyrics = cached
            updateLyric()
            return
        }
        lyrics = nil
        updateLyric()
        isLoadingLyrics = true
        lyricLoadTask = Task { [weak self] in
            guard let self else { return }
            var resolvedTrack = track
            var cached = cachedLyrics(for: track)
            if track.source == .bilibili {
                let exactSubtitleURL = await bilibili.subtitleURL(for: track)
                guard isCurrentLyricLoad(revision, trackID: track.id) else { return }
                if let exactSubtitleURL {
                    resolvedTrack.subtitleURL = exactSubtitleURL
                    if exactSubtitleURL != track.subtitleURL {
                        updateSubtitleURL(exactSubtitleURL, for: track.id)
                        if cached?.source == "Bilibili 字幕" {
                            removeCachedLyrics(for: track)
                            cached = nil
                        }
                    }
                    if cached?.source == "LRCLIB" {
                        removeCachedLyrics(for: track)
                        cached = nil
                    }
                }
            }
            if let cached {
                guard isCurrentLyricLoad(revision, trackID: track.id) else { return }
                lyrics = cached
                updateLyric()
                finishLyricLoad(revision, trackID: track.id)
                return
            }
            let found = await lyricsService.lyrics(for: resolvedTrack)
            guard isCurrentLyricLoad(revision, trackID: track.id) else { return }
            lyrics = found
            if let found {
                cacheLyrics(found, for: track)
                persistLibrary()
            }
            updateLyric()
            finishLyricLoad(revision, trackID: track.id)
        }
    }

    private func cancelLyricLoad() {
        lyricLoadRevision &+= 1
        lyricLoadTask?.cancel()
        lyricLoadTask = nil
        if isLoadingLyrics { isLoadingLyrics = false }
    }

    private func isCurrentLyricLoad(_ revision: UInt64, trackID: String) -> Bool {
        !Task.isCancelled && lyricLoadRevision == revision && currentTrack?.id == trackID
    }

    private func finishLyricLoad(_ revision: UInt64, trackID: String) {
        guard lyricLoadRevision == revision, currentTrack?.id == trackID else { return }
        if isLoadingLyrics { isLoadingLyrics = false }
        lyricLoadTask = nil
    }

    private func refreshCurrentBilibiliSubtitleAfterLogin() async {
        guard let track = currentTrack, track.source == .bilibili,
              let subtitleURL = await bilibili.subtitleURL(for: track) else { return }
        updateSubtitleURL(subtitleURL, for: track.id)
        if cachedLyrics(for: track)?.source == "LRCLIB" {
            removeCachedLyrics(for: track)
        }
        loadLyrics(for: currentTrack ?? track)
    }

    private func updateSubtitleURL(_ url: URL, for trackID: String) {
        if let index = playlist.firstIndex(where: { $0.id == trackID }) {
            playlist[index].subtitleURL = url
            if currentTrack?.id == trackID { currentTrack = playlist[index] }
        } else if currentTrack?.id == trackID {
            currentTrack?.subtitleURL = url
        }
        persistLibrary()
    }

    private func cachedLyrics(for track: MusicTrack) -> LyricsDocument? {
        if let cached = lyricsByTrackID[track.lyricsCacheKey] ?? lyricsByTrackID[track.id] {
            return cached
        }
        guard track.source == .appleMusic,
              let legacy = lyricsByTrackID.first(where: { track.matchesLegacyLyricsCacheKey($0.key) }) else {
            return nil
        }
        lyricsByTrackID[track.lyricsCacheKey] = legacy.value
        lyricsByTrackID.removeValue(forKey: legacy.key)
        persistLibrary()
        return legacy.value
    }

    private func cacheLyrics(_ document: LyricsDocument, for track: MusicTrack) {
        lyricsByTrackID[track.lyricsCacheKey] = document
        if track.lyricsCacheKey != track.id {
            lyricsByTrackID.removeValue(forKey: track.id)
        }
    }

    private func removeCachedLyrics(for track: MusicTrack) {
        lyricsByTrackID.removeValue(forKey: track.lyricsCacheKey)
        lyricsByTrackID.removeValue(forKey: track.id)
        if track.source == .appleMusic {
            lyricsByTrackID.keys
                .filter { track.matchesLegacyLyricsCacheKey($0) }
                .forEach { lyricsByTrackID.removeValue(forKey: $0) }
        }
    }

    private func updateLyric() {
        let adjustedPosition = max(0, position - currentLyricOffset)
        let index = lyrics?.lineIndex(at: adjustedPosition)
        let current = index.flatMap { lyrics?.lines[$0] }
        let nextIndex = index.map { $0 + 1 } ?? 0
        let next = lyrics.flatMap { document in
            document.lines.indices.contains(nextIndex) ? document.lines[nextIndex] : nil
        }
        if currentLyricIndex != index { currentLyricIndex = index }
        if currentLyric != current { currentLyric = current }
        if nextLyric != next { nextLyric = next }
    }

    private func restoreLibrary() async {
        let revisionBeforeLoad = persistenceRevision
        guard let snapshot = try? await library.load() else { return }
        guard persistenceRevision == revisionBeforeLoad else { return }
        playlist = snapshot.playlist
        playMode = snapshot.playMode
        favoriteTrackIDs = snapshot.favoriteTrackIDs
        savedPlaylists = snapshot.savedPlaylists
        lyricOffsets = snapshot.lyricOffsets
        lyricsByTrackID = snapshot.lyricsByTrackID
        currentTrackID = snapshot.currentTrackID
        lastBilibiliPosition = snapshot.lastPosition
        if browsingSource == .bilibili { restoreBilibiliSelection(position: snapshot.lastPosition) }
        else if let currentTrack { loadLyrics(for: currentTrack) }
    }

    private func restoreBilibiliSelection(position savedPosition: TimeInterval = 0) {
        if let id = currentTrackID, let track = playlist.first(where: { $0.id == id }) {
            let restoredPosition = min(max(savedPosition, 0), max(track.duration, 0))
            lastBilibiliPosition = restoredPosition
            currentTrack = track; playbackProgress.reset(position: restoredPosition, duration: track.duration); playbackState = .paused
            loadLyrics(for: track)
        } else if let first = playlist.first {
            lastBilibiliPosition = 0
            currentTrack = first; currentTrackID = first.id; playbackProgress.reset(position: 0, duration: first.duration); playbackState = .paused
            loadLyrics(for: first)
        } else { currentTrack = nil; lastBilibiliPosition = 0; playbackProgress.reset(); playbackState = .stopped }
    }

    private func persistProgressIfNeeded() {
        let second = Int(position)
        guard second != lastSavedSecond, second % 5 == 0 else { return }
        lastSavedSecond = second; persistLibrary()
    }

    private func persistLibrary() {
        persistenceRevision &+= 1
        let revision = persistenceRevision
        let snapshot = librarySnapshot()
        Task { await library.scheduleSave(snapshot, revision: revision) }
    }

    private func librarySnapshot() -> MusicLibrarySnapshot {
        MusicLibrarySnapshot(
            playlist: playlist,
            playMode: playMode,
            currentTrackID: currentTrackID,
            lastPosition: activePlaybackSource == .bilibili ? position : lastBilibiliPosition,
            favoriteTrackIDs: favoriteTrackIDs,
            savedPlaylists: savedPlaylists,
            lyricOffsets: lyricOffsets,
            lyricsByTrackID: lyricsByTrackID
        )
    }
}
