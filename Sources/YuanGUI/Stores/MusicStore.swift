import AppKit
import Combine
import Foundation

@MainActor
final class MusicStore: ObservableObject {
    @Published private(set) var source: MusicSource
    @Published private(set) var playbackState: MusicPlaybackState = .stopped
    @Published private(set) var currentTrack: MusicTrack?
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var volume: Double
    @Published private(set) var playlist: [MusicTrack] = []
    @Published private(set) var playMode: MusicPlayMode = .sequential
    @Published private(set) var favoriteTrackIDs: Set<String> = []
    @Published private(set) var savedPlaylists: [SavedMusicPlaylist] = []
    @Published private(set) var lyrics: LyricsDocument?
    @Published private(set) var currentLyric: TimedLyricLine?
    @Published private(set) var nextLyric: TimedLyricLine?
    @Published private(set) var appleMusicRunning = false
    @Published private(set) var isImporting = false
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
    @Published var isMiniPlayerPresented = false

    private let appleMusic = AppleMusicController()
    private let bilibili = BilibiliClient()
    private let bilibiliPlayer = BilibiliPlayerEngine()
    private let lyricsService = LyricsService()
    private let library = MusicLibraryActor()
    private let defaults: UserDefaults
    private var syncTask: Task<Void, Never>?
    private var lyricLoadTask: Task<Void, Never>?
    private var lyricsSearchTask: Task<Void, Never>?
    private var bilibiliLoadTask: Task<Void, Never>?
    private var lyricsByTrackID: [String: LyricsDocument] = [:]
    private var currentTrackID: String?
    private var lastSavedSecond = -1
    private var bilibiliRefreshAttempted = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.source = MusicSource(rawValue: defaults.string(forKey: "musicSource") ?? "") ?? .appleMusic
        self.volume = defaults.object(forKey: "bilibiliMusicVolume") as? Double ?? 0.8
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
            guard self?.source == .bilibili else { return }
            self?.playbackState = state
        }
        bilibiliPlayer.onProgress = { [weak self] position, duration in
            guard let self, self.source == .bilibili else { return }
            self.position = position
            if duration > 0 { self.duration = duration }
            self.updateLyric()
            self.persistProgressIfNeeded()
        }
        bilibiliPlayer.onFinished = { [weak self] in self?.handleTrackFinished() }
        bilibiliPlayer.onFailure = { [weak self] error in self?.handleBilibiliFailure(error) }
        Task { [weak self] in await self?.restoreLibrary() }
        syncTask = Task { [weak self] in await self?.runSyncLoop() }
    }

    var progress: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }
    var isPlaying: Bool { playbackState.isPlaying }
    var canControl: Bool { source == .appleMusic ? appleMusicRunning : currentTrack != nil }
    var currentLyricOffset: TimeInterval { currentTrack.flatMap { lyricOffsets[$0.id] } ?? 0 }

    func setSource(_ newSource: MusicSource) {
        guard newSource != source else { return }
        switch source {
        case .appleMusic:
            appleMusic.pause()
        case .bilibili:
            bilibiliLoadTask?.cancel()
            bilibiliLoadTask = nil
            bilibiliPlayer.pause()
        }
        source = newSource
        defaults.set(newSource.rawValue, forKey: "musicSource")
        clearTransientPlaybackState()
        if newSource == .bilibili {
            restoreBilibiliSelection()
        } else if appleMusic.hasRequestedAccess {
            refreshAppleMusic()
        } else {
            currentTrack = nil
            position = 0
            duration = 0
            playbackState = appleMusicRunning ? .paused : .stopped
        }
    }

    private func clearTransientPlaybackState() {
        currentTrack = nil
        position = 0
        duration = 0
        playbackState = .stopped
        lyrics = nil
        currentLyric = nil
        nextLyric = nil
        errorMessage = nil
        lyricsSearchMessage = nil
        isSearchingLyrics = false
        lyricLoadTask?.cancel()
        lyricLoadTask = nil
        lyricsSearchTask?.cancel()
        lyricsSearchTask = nil
    }

    func connectAppleMusic() {
        setSource(.appleMusic)
        if !appleMusicRunning {
            appleMusic.openMusic()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.refreshAppleMusic()
            }
        } else {
            refreshAppleMusic()
        }
    }

    func openAppleMusic() { appleMusic.openMusic() }
    func openAutomationSettings() { appleMusic.openAutomationSettings() }

    func playPause() {
        errorMessage = nil
        switch source {
        case .appleMusic:
            bilibiliPlayer.pause()
            guard appleMusicRunning else { connectAppleMusic(); return }
            appleMusic.playPause()
            scheduleAppleRefresh()
        case .bilibili:
            appleMusic.pause()
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
        position = min(max(newPosition, 0), max(duration, 0))
        source == .appleMusic ? appleMusic.seek(to: position) : bilibiliPlayer.seek(to: position)
        updateLyric()
    }

    func setVolume(_ newValue: Double) {
        volume = min(max(newValue, 0), 1)
        if source == .appleMusic { appleMusic.setVolume(volume) }
        else {
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
                if let first = added.first ?? tracks.first { play(first) }
            } catch { errorMessage = error.localizedDescription }
            isImporting = false
        }
    }

    func play(_ track: MusicTrack, at savedPosition: TimeInterval = 0) {
        guard track.source == .bilibili else { return }
        setSource(.bilibili)
        appleMusic.pause()
        currentTrack = track
        currentTrackID = track.id
        duration = track.duration
        position = savedPosition
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
                      source == .bilibili,
                      currentTrack?.id == track.id else { return }
                bilibiliPlayer.load(urls: location.candidates, headers: headers, position: savedPosition)
                persistLibrary()
            } catch {
                guard !Task.isCancelled, source == .bilibili else { return }
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
        lyricsByTrackID.removeValue(forKey: track.id)
        for index in savedPlaylists.indices { savedPlaylists[index].trackIDs.removeAll { $0 == track.id } }
        if wasCurrent {
            bilibiliPlayer.stop(); currentTrack = nil; currentTrackID = nil; playbackState = .stopped
            lyrics = nil; currentLyric = nil; nextLyric = nil
        }
        persistLibrary()
    }

    func clearPlaylist() {
        for track in playlist { lyricsByTrackID.removeValue(forKey: track.id) }
        bilibiliPlayer.stop(); playlist.removeAll(); favoriteTrackIDs.removeAll(); savedPlaylists.removeAll()
        currentTrack = nil; currentTrackID = nil; playbackState = .stopped
        lyrics = nil; currentLyric = nil; nextLyric = nil; persistLibrary()
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
        lyricLoadTask?.cancel()
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
                lyricsByTrackID[track.id] = found
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
        let document = LyricsParser.parseLRC(text)
        lyrics = document
        if let trackID = currentTrack?.id {
            lyricsByTrackID[trackID] = document
            persistLibrary()
        }
        updateLyric()
    }

    func showFullPlayer() { NotificationCenter.default.post(name: .showYuanGUIMusic, object: nil) }

    func shutdown() {
        syncTask?.cancel(); lyricLoadTask?.cancel(); lyricsSearchTask?.cancel(); bilibiliLoadTask?.cancel(); bilibiliPlayer.stop()
        Task { await library.flush() }
    }

    private func refreshAppleMusic() {
        let running = appleMusic.isRunning
        if appleMusicRunning != running { appleMusicRunning = running }
        guard appleMusicRunning else { playbackState = .stopped; return }
        do {
            let snapshot = try appleMusic.requestSnapshot()
            guard source == .appleMusic else { return }
            let changed = currentTrack?.id != snapshot.track?.id
            currentTrack = snapshot.track
            playbackState = snapshot.state
            position = snapshot.position
            duration = snapshot.track?.duration ?? 0
            volume = snapshot.volume
            if changed, let track = snapshot.track { loadLyrics(for: track) }
            updateLyric()
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func runSyncLoop() async {
        while !Task.isCancelled {
            let running = appleMusic.isRunning
            if appleMusicRunning != running { appleMusicRunning = running }
            if source == .appleMusic, appleMusic.hasRequestedAccess { refreshAppleMusic() }
            let seconds = source == .appleMusic && playbackState.isPlaying ? 1.0 : 3.0
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
        }
    }

    private func scheduleAppleRefresh() {
        Task { [weak self] in try? await Task.sleep(for: .milliseconds(250)); self?.refreshAppleMusic() }
    }

    private func move(by delta: Int) {
        if source == .appleMusic {
            delta < 0 ? appleMusic.previous() : appleMusic.next(); scheduleAppleRefresh(); return
        }
        guard !playlist.isEmpty else { return }
        let current = playlist.firstIndex(where: { $0.id == currentTrack?.id }) ?? 0
        let target = current + delta
        if playlist.indices.contains(target) { play(playlist[target]) }
        else if playMode == .repeatAll { play(delta < 0 ? playlist.last! : playlist.first!) }
    }

    private func handleTrackFinished() {
        if playMode == .repeatOne, let currentTrack { play(currentTrack) }
        else { move(by: 1) }
    }

    private func handleBilibiliFailure(_ error: Error) {
        guard source == .bilibili, let track = currentTrack else { return }
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
        lyricLoadTask?.cancel()
        lyricLoadTask = nil
        isSearchingLyrics = false
        lyricsSearchMessage = nil
        if let cached = lyricsByTrackID[track.id] {
            lyrics = cached
            updateLyric()
            return
        }
        lyrics = nil; currentLyric = nil; nextLyric = nil
        lyricLoadTask = Task { [weak self] in
            guard let self else { return }
            let found = await lyricsService.lyrics(for: track)
            guard !Task.isCancelled, currentTrack?.id == track.id else { return }
            lyrics = found
            if let found {
                lyricsByTrackID[track.id] = found
                persistLibrary()
            }
            updateLyric()
        }
    }

    private func updateLyric() {
        let adjustedPosition = max(0, position - currentLyricOffset)
        currentLyric = lyrics?.line(at: adjustedPosition)
        nextLyric = lyrics?.nextLine(after: adjustedPosition)
    }

    private func restoreLibrary() async {
        guard let snapshot = try? await library.load() else { return }
        playlist = snapshot.playlist
        playMode = snapshot.playMode
        favoriteTrackIDs = snapshot.favoriteTrackIDs
        savedPlaylists = snapshot.savedPlaylists
        lyricOffsets = snapshot.lyricOffsets
        lyricsByTrackID = snapshot.lyricsByTrackID
        currentTrackID = snapshot.currentTrackID
        if source == .bilibili { restoreBilibiliSelection(position: snapshot.lastPosition) }
    }

    private func restoreBilibiliSelection(position savedPosition: TimeInterval = 0) {
        if let id = currentTrackID, let track = playlist.first(where: { $0.id == id }) {
            currentTrack = track; duration = track.duration; position = savedPosition; playbackState = .paused
            loadLyrics(for: track)
        } else if let first = playlist.first {
            currentTrack = first; currentTrackID = first.id; duration = first.duration; position = 0; playbackState = .paused
            loadLyrics(for: first)
        } else { currentTrack = nil; position = 0; duration = 0; playbackState = .stopped }
    }

    private func persistProgressIfNeeded() {
        let second = Int(position)
        guard second != lastSavedSecond, second % 5 == 0 else { return }
        lastSavedSecond = second; persistLibrary()
    }

    private func persistLibrary() {
        let snapshot = MusicLibrarySnapshot(
            playlist: playlist,
            playMode: playMode,
            currentTrackID: currentTrackID,
            lastPosition: position,
            favoriteTrackIDs: favoriteTrackIDs,
            savedPlaylists: savedPlaylists,
            lyricOffsets: lyricOffsets,
            lyricsByTrackID: lyricsByTrackID
        )
        Task { await library.scheduleSave(snapshot) }
    }
}
