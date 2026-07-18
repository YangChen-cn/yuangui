import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

struct MusicArtworkView: View {
    let track: MusicTrack?
    var size: CGFloat = 54

    var body: some View {
        Group {
            if let url = displayCoverURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { placeholder }
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.18).stroke(.white.opacity(0.28), lineWidth: 0.7))
    }

    private var displayCoverURL: URL? {
        guard let url = track?.coverURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return track?.coverURL
        }
        if components.scheme?.lowercased() == "http" { components.scheme = "https" }
        return components.url
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.pink.opacity(0.72), .purple.opacity(0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: track?.source.systemImage ?? "music.note")
                .font(.system(size: size * 0.34, weight: .semibold)).foregroundStyle(.white)
        }
    }
}

struct MusicTransportControls: View {
    @ObservedObject var music: MusicStore
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 15 : 22) {
            Button(action: music.previous) { Image(systemName: "backward.fill") }
                .help("上一首")
                .accessibilityLabel("上一首")
            Button(action: music.playPause) {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: compact ? 15 : 20, weight: .bold))
                    .frame(width: compact ? 27 : 38, height: compact ? 27 : 38)
                    .background(.primary.opacity(0.10), in: Circle())
            }
            .help(music.isPlaying ? "暂停" : "播放")
            .accessibilityLabel(music.isPlaying ? "暂停" : "播放")
            Button(action: music.next) { Image(systemName: "forward.fill") }
                .help("下一首")
                .accessibilityLabel("下一首")
        }
        .buttonStyle(.plain)
        .disabled(!music.canControl)
    }
}

struct MusicProgressView: View {
    let music: MusicStore
    @ObservedObject private var progress: MusicPlaybackProgress
    @State private var previewPosition: TimeInterval = 0
    @State private var isSeeking = false

    init(music: MusicStore) {
        self.music = music
        _progress = ObservedObject(wrappedValue: music.playbackProgress)
    }

    var body: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { isSeeking ? previewPosition : progress.position },
                    set: { newPosition in
                        previewPosition = newPosition
                        if !isSeeking { music.seek(to: newPosition) }
                    }
                ),
                in: 0...max(progress.duration, 1),
                onEditingChanged: handleSeeking
            )
                .controlSize(.mini)
                .disabled(progress.duration <= 0)
                .help("拖动调整播放位置")
                .accessibilityLabel("播放进度")
            HStack {
                Text(formatTime(isSeeking ? previewPosition : progress.position))
                Spacer()
                Text(formatTime(progress.duration))
            }
            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    private func handleSeeking(_ editing: Bool) {
        if editing {
            previewPosition = progress.position
            isSeeking = true
        } else if isSeeking {
            let target = previewPosition
            isSeeking = false
            music.seek(to: target)
        }
    }
}

private struct FullPlayerLyricsView: View {
    @ObservedObject var music: MusicStore
    @State private var previewLyricPosition: Double?
    @State private var isScrollFocused = false
    @State private var resumeFollowingTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("歌词", systemImage: "quote.bubble")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let source = music.lyrics?.source, !source.isEmpty {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            lyricContent
        }
        .padding(14)
        .frame(maxWidth: 520)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(isScrollFocused ? 0.65 : 0), lineWidth: 1.5)
        }
        .overlay(LyricsScrollWheelMonitor(
            isEnabled: music.lyrics?.lines.isEmpty == false,
            isActive: isScrollFocused,
            onActivationChange: setScrollFocus,
            onScroll: previewLyrics
        ))
        .help(isScrollFocused
            ? "歌词滚动已选中；点击播放器空白处退出，点击歌词可跳转"
            : "点击选中歌词区域，再上下滚动预览；点击歌词可跳转")
        .onDisappear { resumeFollowingTask?.cancel() }
    }

    @ViewBuilder
    private var lyricContent: some View {
        if music.currentTrack == nil {
            lyricStatus("播放歌曲后显示歌词", systemImage: "music.note")
        } else if music.isLoadingLyrics {
            VStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("正在加载歌词").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 264)
        } else if let document = music.lyrics, !document.lines.isEmpty {
            lyricRows(document)
        } else {
            lyricStatus("暂无同步歌词", systemImage: "text.badge.xmark")
        }
    }

    private func lyricRows(_ document: LyricsDocument) -> some View {
        let currentPosition = previewLyricPosition ?? Double(music.currentLyricIndex ?? 0)
        let center = min(max(Int(currentPosition.rounded()), 0), document.lines.count - 1)
        let candidates = Array((center - 4)...(center + 4))
        let rowOffset = CGFloat(Double(center) - currentPosition) * 38
        return ZStack {
            VStack(spacing: 0) {
                ForEach(candidates, id: \.self) { lineIndex in
                    if document.lines.indices.contains(lineIndex) {
                        lyricButton(
                            document.lines[lineIndex],
                            isCurrent: lineIndex == music.currentLyricIndex,
                            distance: min(abs(lineIndex - center), 3)
                        )
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
            .offset(y: rowOffset)
        }
        .frame(height: 266)
        .clipped()
    }

    private func lyricButton(_ line: TimedLyricLine, isCurrent: Bool, distance: Int) -> some View {
        Button {
            resumeFollowingTask?.cancel()
            withAnimation(.easeOut(duration: 0.16)) { previewLyricPosition = nil }
            music.seek(toLyric: line)
        } label: {
            Text(line.text)
                .font(.system(
                    size: isCurrent ? 16 : 13,
                    weight: isCurrent ? .semibold : .regular,
                    design: .rounded
                ))
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary.opacity(max(0.42, 0.82 - Double(distance) * 0.12)))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isScrollFocused)
        .help("跳转到 \(formatTime(line.time + music.currentLyricOffset))")
        .accessibilityLabel("\(formatTime(line.time + music.currentLyricOffset))，\(line.text)")
        .accessibilityHint("跳转到这句歌词")
    }

    private func lyricStatus(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 264)
    }

    private func previewLyrics(_ delta: CGFloat) {
        guard let document = music.lyrics, !document.lines.isEmpty, abs(delta) > 0.01 else { return }
        let current = previewLyricPosition ?? Double(music.currentLyricIndex ?? 0)
        let target = min(max(current - Double(delta / 38), 0), Double(document.lines.count - 1))
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.88)) {
            previewLyricPosition = target
        }
        resumeFollowingTask?.cancel()
        resumeFollowingTask = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            withAnimation(.easeOut(duration: 0.2)) { previewLyricPosition = nil }
        }
    }

    private func setScrollFocus(_ focused: Bool) {
        guard focused != isScrollFocused else { return }
        isScrollFocused = focused
        if !focused {
            resumeFollowingTask?.cancel()
            withAnimation(.easeOut(duration: 0.18)) { previewLyricPosition = nil }
        }
    }
}

private struct LyricsScrollWheelMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let isActive: Bool
    let onActivationChange: (Bool) -> Void
    let onScroll: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isEnabled: isEnabled,
            isActive: isActive,
            onActivationChange: onActivationChange,
            onScroll: onScroll
        )
    }

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.isActive = isActive
        context.coordinator.onActivationChange = onActivationChange
        context.coordinator.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class MonitorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    final class Coordinator {
        var isEnabled: Bool
        var isActive: Bool
        var onActivationChange: (Bool) -> Void
        var onScroll: (CGFloat) -> Void
        private weak var view: MonitorView?
        private var eventMonitor: Any?

        init(
            isEnabled: Bool,
            isActive: Bool,
            onActivationChange: @escaping (Bool) -> Void,
            onScroll: @escaping (CGFloat) -> Void
        ) {
            self.isEnabled = isEnabled
            self.isActive = isActive
            self.onActivationChange = onActivationChange
            self.onScroll = onScroll
        }

        func attach(to view: MonitorView) {
            self.view = view
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .scrollWheel]) { [weak self] event in
                guard let self, let monitoredView = self.view, event.window === monitoredView.window else { return event }
                let isInside = monitoredView.bounds.contains(monitoredView.convert(event.locationInWindow, from: nil))
                if event.type == .leftMouseDown {
                    onActivationChange(isInside && isEnabled)
                    return event
                }
                guard isActive else { return event }
                let delta = event.hasPreciseScrollingDeltas
                    ? event.scrollingDeltaY
                    : event.scrollingDeltaY * 12
                onScroll(delta)
                return nil
            }
        }

        func detach() {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            view = nil
        }

        deinit { detach() }
    }
}

struct MiniMusicPlayerView: View {
    @ObservedObject var music: MusicStore
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MusicArtworkView(track: music.currentTrack, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(music.currentTrack?.title ?? "暂无播放内容").font(.headline).lineLimit(1)
                    Text(music.currentTrack?.artist ?? music.playbackSource.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Label(music.playbackSource.title, systemImage: music.playbackSource.systemImage)
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            MusicProgressView(music: music)
            HStack {
                Button { music.toggleLyricsVisible() } label: {
                    Image(systemName: music.lyricsVisible ? "quote.bubble.fill" : "quote.bubble")
                }.help(music.lyricsVisible ? "隐藏桌面歌词" : "显示桌面歌词")
                Button { music.setLyricsPanelLocked(!music.lyricsPanelLocked) } label: {
                    Image(systemName: music.lyricsPanelLocked ? "lock.fill" : "lock.open")
                }.help(music.lyricsPanelLocked ? "解锁桌面歌词" : "锁定桌面歌词")
                Spacer()
                MusicTransportControls(music: music, compact: true)
                Spacer()
                Button { music.showFullPlayer() } label: { Image(systemName: "list.bullet") }.help("打开完整播放器")
            }.buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 300)
    }
}

struct MusicStatusCard: View {
    @ObservedObject var music: MusicStore
    @State private var searchTitle = ""
    @State private var searchArtist = ""
    @State private var selectedLibraryID = "queue"

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                nowPlayingSection
                if music.source == .bilibili { bilibiliLibrarySection }
                else { appleMusicQueueSection }
                playbackSettingsSection
            }
            .padding(.horizontal, 1)
            .padding(.bottom, 2)
        }
        .onAppear(perform: syncSearchFields)
        .onChange(of: music.currentTrack?.id) { _, _ in syncSearchFields() }
        .onChange(of: music.source) { _, _ in
            selectedLibraryID = "queue"
            syncSearchFields()
        }
    }

    private var nowPlayingSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(music.currentTrack == nil ? "音乐" : "正在播放", systemImage: music.playbackSource.systemImage)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                if let track = music.currentTrack, track.source == .bilibili {
                    Button { music.toggleFavorite(track) } label: {
                        Image(systemName: music.isFavorite(track) ? "heart.fill" : "heart")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(music.isFavorite(track) ? .pink : .secondary)
                    .help(music.isFavorite(track) ? "取消收藏当前歌曲" : "收藏当前歌曲")
                }
                Button { music.showFullPlayer() } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.plain)
                    .help("打开完整播放器")
            }
            if let track = music.currentTrack {
                HStack(spacing: 11) {
                    MusicArtworkView(track: track, size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(2)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Label(track.source.title, systemImage: track.source.systemImage)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                MusicProgressView(music: music)
                HStack {
                    MusicTransportControls(music: music, compact: true)
                    Spacer()
                    Toggle("桌面歌词", isOn: Binding(
                        get: { music.lyricsVisible },
                        set: { _ in music.toggleLyricsVisible() }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            } else {
                Text("暂无播放内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(music.source == .appleMusic ? "打开 Apple Music" : "导入 B 站歌曲…") {
                    if music.source == .appleMusic { music.connectAppleMusic() }
                    else { music.showFullPlayer() }
                }
                .controlSize(.small)
            }
        }
        .musicDashboardSection()
    }

    private var playbackSettingsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("播放与歌词", systemImage: "slider.horizontal.3")
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Picker("浏览来源", selection: Binding(get: { music.source }, set: music.setSource)) {
                ForEach(MusicSource.allCases) { source in
                    Label(source.title, systemImage: source.systemImage).tag(source)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                Text("歌词偏移").font(.caption)
                LyricOffsetControl(music: music, compact: true)
            }
            if music.source == .bilibili, music.currentTrack?.source == .bilibili {
                VStack(alignment: .leading, spacing: 5) {
                    Text("歌曲信息与歌词匹配")
                        .font(.caption.weight(.semibold))
                    HStack {
                        TextField("歌曲名", text: $searchTitle)
                        TextField("歌手", text: $searchArtist)
                    }
                    HStack {
                        Button {
                            music.updateCurrentTrackMetadata(title: searchTitle, artist: searchArtist)
                        } label: {
                            Label("仅保存歌曲信息", systemImage: "square.and.arrow.down")
                        }
                        .disabled(searchTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && searchArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button {
                            music.searchLyrics(title: searchTitle, artist: searchArtist)
                        } label: {
                            if music.isSearchingLyrics { ProgressView().controlSize(.mini) }
                            else { Label("匹配歌词并更新信息", systemImage: "text.magnifyingglass") }
                        }
                        .disabled(music.isSearchingLyrics || searchTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                    }
                    .controlSize(.small)
                    if let message = music.lyricsSearchMessage {
                        Text(message)
                            .font(.system(size: 9))
                            .foregroundStyle(message.hasPrefix("已") ? Color.green : Color.orange)
                    }
                }
            }
        }
        .musicDashboardSection()
    }

    private var bilibiliLibrarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Bilibili 资料库", systemImage: "music.note.list")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                if let track = music.currentTrack, track.source == .bilibili {
                    Menu {
                        if music.savedPlaylists.isEmpty { Text("尚未创建歌单") }
                        else {
                            ForEach(music.savedPlaylists) { playlist in
                                Button(playlist.name) { music.add(track, to: playlist) }
                            }
                        }
                    } label: { Image(systemName: "text.badge.plus") }
                    .menuStyle(.borderlessButton)
                    .frame(width: 22)
                    .help("把当前歌曲加入歌单")
                }
            }
            Menu {
                Button("当前播放列表（\(music.playlist.count)）") { selectedLibraryID = "queue" }
                Button("收藏歌曲（\(music.favoriteTracks.count)）") { selectedLibraryID = "favorites" }
                if !music.savedPlaylists.isEmpty { Divider() }
                ForEach(music.savedPlaylists) { playlist in
                    Button("\(playlist.name)（\(music.tracks(in: playlist).count)）") {
                        selectedLibraryID = "playlist:\(playlist.id.uuidString)"
                    }
                }
            } label: {
                HStack {
                    Text(selectedLibraryTitle)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .padding(.horizontal, 9)
                .frame(height: 27)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.borderlessButton)

            if selectedLibraryTracks.isEmpty {
                Text("这个列表里还没有歌曲")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(selectedLibraryTracks.prefix(4))) { track in
                    Button { music.play(track) } label: {
                        HStack(spacing: 8) {
                            MusicArtworkView(track: track, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                                Text(track.artist).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text(formatTime(track.duration))
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Image(systemName: music.currentTrack?.id == track.id && music.isPlaying ? "speaker.wave.2.fill" : "play.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(music.currentTrack?.id == track.id ? .pink : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if selectedLibraryTracks.count > 4 {
                    Text("还有 \(selectedLibraryTracks.count - 4) 首，请在完整资料库中查看")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                }
            }
            Button("打开完整资料库…") { music.showFullPlayer() }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .musicDashboardSection()
    }

    private var appleMusicQueueSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.house.fill")
                .foregroundStyle(.pink)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Music 播放队列")
                    .font(.caption.weight(.semibold))
                Text("队列和资料库继续由 Music App 管理。")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 5) {
                Button("连接控制") { music.connectAppleMusic() }
                Button("打开 Music") { music.openAppleMusic() }
            }
            .controlSize(.small)
        }
        .musicDashboardSection()
    }

    private var selectedLibraryTracks: [MusicTrack] {
        if selectedLibraryID == "favorites" { return music.favoriteTracks }
        if selectedLibraryID.hasPrefix("playlist:"),
           let id = UUID(uuidString: String(selectedLibraryID.dropFirst("playlist:".count))),
           let playlist = music.savedPlaylists.first(where: { $0.id == id }) {
            return music.tracks(in: playlist)
        }
        return music.playlist
    }

    private var selectedLibraryTitle: String {
        if selectedLibraryID == "favorites" { return "收藏歌曲（\(music.favoriteTracks.count)）" }
        if selectedLibraryID.hasPrefix("playlist:"),
           let id = UUID(uuidString: String(selectedLibraryID.dropFirst("playlist:".count))),
           let playlist = music.savedPlaylists.first(where: { $0.id == id }) {
            return "\(playlist.name)（\(music.tracks(in: playlist).count)）"
        }
        return "当前播放列表（\(music.playlist.count)）"
    }

    private func syncSearchFields() {
        searchTitle = music.currentTrack?.title ?? ""
        searchArtist = music.currentTrack?.artist ?? ""
    }
}

private extension View {
    func musicDashboardSection() -> some View {
        padding(10)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.24), lineWidth: 0.6))
    }
}

struct MusicPlayerView: View {
    @ObservedObject var music: MusicStore
    @State private var selectedTrackID: String?
    @State private var selectedCollectionID = "all"
    @State private var isCreatingPlaylist = false
    @State private var newPlaylistName = ""
    @State private var isSearchingLyrics = false
    @State private var isBilibiliLoginPresented = false
    @State private var isBilibiliFavoritesPresented = false
    @State private var lyricsSearchTitle = ""
    @State private var lyricsSearchArtist = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("浏览来源", selection: Binding(get: { music.source }, set: music.setSource)) {
                ForEach(MusicSource.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 310)
            .padding(.vertical, 10)
            Divider()
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 330)
            } detail: {
                detail
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { selectedTrackID = music.currentTrack?.id }
        .alert("新建歌单", isPresented: $isCreatingPlaylist) {
            TextField("歌单名称", text: $newPlaylistName)
            Button("创建") { createPlaylist() }
            Button("取消", role: .cancel) { newPlaylistName = "" }
        } message: {
            Text("歌单只保存在这台 Mac 上。")
        }
        .sheet(isPresented: $isSearchingLyrics) {
            LyricsSearchSheet(
                music: music,
                title: $lyricsSearchTitle,
                artist: $lyricsSearchArtist,
                isPresented: $isSearchingLyrics
            )
        }
        .sheet(isPresented: $isBilibiliLoginPresented) {
            BilibiliLoginSheet(music: music, isPresented: $isBilibiliLoginPresented)
        }
        .sheet(isPresented: $isBilibiliFavoritesPresented) {
            BilibiliFavoriteImportSheet(music: music, isPresented: $isBilibiliFavoritesPresented)
        }
    }

    @ViewBuilder private var sidebar: some View {
        if music.source == .appleMusic {
            List {
                Section("Apple Music") {
                    Label(music.appleMusicRunning ? "Music 正在运行" : "Music 尚未运行", systemImage: "music.note")
                    Button("连接并控制 Music App") { music.connectAppleMusic() }
                    Button("打开 Music App") { music.openAppleMusic() }
                }
            }.listStyle(.sidebar)
        } else {
            VStack(spacing: 0) {
                HStack {
                    TextField("粘贴 URL 或输入 BV 号", text: $music.importText)
                        .onSubmit(music.importBilibili)
                    Button { music.importBilibili() } label: {
                        music.isImporting ? AnyView(ProgressView().controlSize(.small)) : AnyView(Image(systemName: "plus"))
                    }.disabled(music.isImporting || music.importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(10)
                if let message = music.bilibiliImportMessage {
                    VStack(alignment: .leading, spacing: 7) {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                        HStack(spacing: 8) {
                            Button("开始播放") { music.playLastBilibiliImport() }
                                .buttonStyle(.borderedProminent)
                            Button("继续浏览") { music.dismissBilibiliImportResult() }
                                .buttonStyle(.bordered)
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
                HStack {
                    Button {
                        if music.bilibiliAccount == nil { isBilibiliLoginPresented = true }
                        else { isBilibiliFavoritesPresented = true }
                    } label: {
                        Label(
                            music.bilibiliAccount == nil ? "登录后导入收藏夹" : "导入哔哩哔哩收藏夹",
                            systemImage: "folder.badge.plus"
                        )
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
                List(selection: $selectedTrackID) {
                    Section("资料库") {
                        collectionButton("播放列表", systemImage: "music.note.list", id: "all", count: music.playlist.count)
                        collectionButton("收藏", systemImage: "heart.fill", id: "favorites", count: music.favoriteTracks.count)
                    }
                    Section {
                        ForEach(music.savedPlaylists) { savedPlaylist in
                            collectionButton(savedPlaylist.name, systemImage: "music.note.house", id: "playlist:\(savedPlaylist.id.uuidString)", count: music.tracks(in: savedPlaylist).count)
                                .contextMenu {
                                    Button("删除歌单", role: .destructive) {
                                        music.deletePlaylist(savedPlaylist)
                                        if selectedCollectionID == "playlist:\(savedPlaylist.id.uuidString)" { selectedCollectionID = "all" }
                                    }
                                }
                        }
                        Button { isCreatingPlaylist = true } label: { Label("新建歌单", systemImage: "plus") }
                    } header: { Text("我的歌单") }

                    Section(collectionTitle) {
                    ForEach(displayedTracks) { track in
                        HStack(spacing: 8) {
                            Image(systemName: music.currentTrack?.id == track.id && music.isPlaying ? "speaker.wave.2.fill" : "music.note")
                                .foregroundStyle(music.currentTrack?.id == track.id ? .pink : .secondary).frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title).lineLimit(1)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .tag(track.id)
                        .contextMenu {
                            Button("播放") { music.play(track) }
                            Button(music.isFavorite(track) ? "取消收藏" : "收藏") { music.toggleFavorite(track) }
                            if !music.savedPlaylists.isEmpty {
                                Menu("加入歌单") {
                                    ForEach(music.savedPlaylists) { savedPlaylist in
                                        Button(savedPlaylist.name) { music.add(track, to: savedPlaylist) }
                                    }
                                }
                            }
                            if let selectedSavedPlaylist {
                                Button("从此歌单移除") { music.remove(track, from: selectedSavedPlaylist) }
                            }
                            Button("从资料库移除", role: .destructive) { music.remove(track) }
                        }
                        .onTapGesture(count: 2) { music.play(track) }
                    }
                    }
                }.listStyle(.sidebar)
                HStack {
                    Text("\(displayedTracks.count) 首").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if selectedCollectionID == "all", !music.playlist.isEmpty {
                        Button("清空") { music.clearPlaylist() }.buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }.padding(10)
            }
        }
    }

    private var detail: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack(alignment: .topTrailing) {
                    MusicArtworkView(track: music.currentTrack, size: 190)
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                        .frame(maxWidth: .infinity)
                    if music.source == .bilibili {
                        bilibiliAccountButton
                    }
                }
                VStack(spacing: 4) {
                    Text(music.currentTrack?.title ?? emptyTitle).font(.system(size: 24, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                    Text(music.currentTrack?.artist ?? music.playbackSource.title).foregroundStyle(.secondary)
                    if let album = music.currentTrack?.album, !album.isEmpty { Text(album).font(.caption).foregroundStyle(.tertiary) }
                }
                MusicProgressView(music: music).frame(maxWidth: 480)
                MusicTransportControls(music: music)
                if let track = music.currentTrack, track.source == .bilibili {
                    Button { music.toggleFavorite(track) } label: {
                        Label(music.isFavorite(track) ? "已收藏" : "收藏", systemImage: music.isFavorite(track) ? "heart.fill" : "heart")
                    }
                    .buttonStyle(.bordered)
                    .tint(.pink)
                }
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                    Slider(value: Binding(get: { music.volume }, set: music.setVolume), in: 0...1).frame(width: 160)
                    if music.source == .bilibili {
                        Picker("播放模式", selection: Binding(get: { music.playMode }, set: music.setPlayMode)) {
                            ForEach(MusicPlayMode.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                        }.labelsHidden().frame(width: 120)
                    }
                }
                FullPlayerLyricsView(music: music)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { lyricsActionButtons }
                    VStack(alignment: .leading, spacing: 7) { lyricsActionButtons }
                }
                lyricsAdjustments
                if let error = music.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                    if music.playbackSource == .appleMusic { Button("打开自动化权限设置") { music.openAutomationSettings() } }
                }
            }
            .padding(28).frame(maxWidth: .infinity)
        }
    }

    private var bilibiliAccountButton: some View {
        Button { isBilibiliLoginPresented = true } label: {
            HStack(spacing: 7) {
                if let account = music.bilibiliAccount {
                    AsyncImage(url: account.avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(verbatim: "UID \(account.mid)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(width: 136, alignment: .leading)
                } else {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 17, weight: .semibold))
                    Text("登录哔哩哔哩")
                        .font(.callout.weight(.semibold))
                }
            }
            .padding(.horizontal, 4)
            .frame(width: music.bilibiliAccount == nil ? 148 : 175, alignment: .leading)
            .frame(minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .fixedSize(horizontal: true, vertical: true)
        .offset(x: music.bilibiliAccount == nil ? 0 : 20)
        .help(music.bilibiliAccount.map { "已登录：\($0.name)，点击管理账号" } ?? "扫码登录哔哩哔哩")
    }

    private var emptyTitle: String { music.source == .appleMusic ? "连接 Apple Music" : "从左侧导入并选择歌曲" }

    @ViewBuilder
    private var lyricsActionButtons: some View {
        Button(music.lyricsVisible ? "隐藏桌面歌词" : "显示桌面歌词") { music.toggleLyricsVisible() }
        Button("导入 LRC 文件") { chooseLRC() }
        Button("修改歌曲信息或匹配歌词") { prepareLyricsSearch() }
    }

    private var lyricsAdjustments: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("歌词偏移")
                LyricOffsetControl(music: music)
            }
            Text("正数会让歌词延后出现，负数会让歌词提前出现。偏移按歌曲保存。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label("桌面歌词字号", systemImage: "textformat.size")
                Slider(
                    value: Binding(get: { music.lyricsFontSize }, set: music.setLyricsFontSize),
                    in: 14...42,
                    step: 1
                )
                .frame(width: 150)
                Text("\(Int(music.lyricsFontSize))")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 24)
                Picker("字体", selection: Binding(
                    get: { music.lyricsFontStyle },
                    set: music.setLyricsFontStyle
                )) {
                    ForEach(LyricsFontStyle.allCases) { style in Text(style.title).tag(style) }
                }
                .labelsHidden()
                .frame(width: 100)
                ColorPicker(
                    "颜色",
                    selection: Binding(
                        get: { Color(nsColor: music.lyricsColor) },
                        set: { music.setLyricsColor(NSColor($0)) }
                    ),
                    supportsOpacity: true
                )
                .fixedSize()
                Toggle("锁定并点击穿透", isOn: Binding(
                    get: { music.lyricsPanelLocked },
                    set: music.setLyricsPanelLocked
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var selectedSavedPlaylist: SavedMusicPlaylist? {
        guard selectedCollectionID.hasPrefix("playlist:"),
              let id = UUID(uuidString: String(selectedCollectionID.dropFirst("playlist:".count))) else { return nil }
        return music.savedPlaylists.first { $0.id == id }
    }

    private var displayedTracks: [MusicTrack] {
        if selectedCollectionID == "favorites" { return music.favoriteTracks }
        if let selectedSavedPlaylist { return music.tracks(in: selectedSavedPlaylist) }
        return music.playlist
    }

    private var collectionTitle: String {
        if selectedCollectionID == "favorites" { return "收藏歌曲" }
        return selectedSavedPlaylist?.name ?? "播放列表"
    }

    private func collectionButton(_ title: String, systemImage: String, id: String, count: Int) -> some View {
        Button { selectedCollectionID = id } label: {
            HStack {
                Label(title, systemImage: systemImage).lineLimit(1)
                Spacer()
                Text("\(count)").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedCollectionID == id ? Color.accentColor : Color.primary)
    }

    private func createPlaylist() {
        if let created = music.createPlaylist(named: newPlaylistName) {
            selectedCollectionID = "playlist:\(created.id.uuidString)"
        }
        newPlaylistName = ""
    }

    private func chooseLRC() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]
        if panel.runModal() == .OK, let url = panel.url { music.importLRC(from: url) }
    }

    private func prepareLyricsSearch() {
        lyricsSearchTitle = music.currentTrack?.title ?? ""
        lyricsSearchArtist = music.currentTrack?.artist ?? ""
        isSearchingLyrics = true
    }
}

struct BilibiliFavoriteImportSheet: View {
    @ObservedObject var music: MusicStore
    @Binding var isPresented: Bool
    @State private var selectedFolderID: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("导入哔哩哔哩收藏夹", systemImage: "folder.badge.plus")
                    .font(.title2.bold())
                Spacer()
                if let account = music.bilibiliAccount {
                    Text(account.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text("选择一个收藏夹后，YuanGUI 会去重加入播放列表，并创建或更新同名本地歌单。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if music.isLoadingBilibiliFavoriteFolders {
                ProgressView("正在读取收藏夹…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if music.bilibiliFavoriteFolders.isEmpty {
                ContentUnavailableView(
                    "没有可导入的收藏夹",
                    systemImage: "folder",
                    description: Text(music.bilibiliFavoriteMessage ?? "请确认账号已登录，并尝试刷新。")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $selectedFolderID) {
                    ForEach(BilibiliFavoriteFolderKind.allCases, id: \.self) { kind in
                        let folders = music.bilibiliFavoriteFolders.filter { $0.kind == kind }
                        if !folders.isEmpty {
                            Section(kind.title) {
                                ForEach(folders) { folder in
                                    HStack(spacing: 10) {
                                        AsyncImage(url: folder.coverURL) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: {
                                            Image(systemName: "folder.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 42, height: 42)
                                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(folder.title).lineLimit(1)
                                            HStack(spacing: 6) {
                                                Text("\(folder.mediaCount) 个视频")
                                                if let owner = folder.ownerName, folder.kind == .collected {
                                                    Text("· \(owner)").lineLimit(1)
                                                }
                                            }
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .tag(folder.id)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            if music.isImportingBilibiliFavoriteFolder {
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(
                        value: Double(music.bilibiliFavoriteImportCompleted),
                        total: Double(max(music.bilibiliFavoriteImportTotal, 1))
                    )
                    Text("正在解析视频 \(music.bilibiliFavoriteImportCompleted)/\(music.bilibiliFavoriteImportTotal)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let message = music.bilibiliFavoriteMessage,
                      !music.bilibiliFavoriteFolders.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.hasPrefix("已从") ? Color.green : Color.orange)
            }

            HStack {
                Button("刷新") { music.loadBilibiliFavoriteFolders() }
                    .disabled(music.isLoadingBilibiliFavoriteFolders || music.isImportingBilibiliFavoriteFolder)
                Spacer()
                Button("完成") { isPresented = false }
                    .disabled(music.isImportingBilibiliFavoriteFolder)
                Button("一键导入") {
                    if let selectedFolder { music.importBilibiliFavoriteFolder(selectedFolder) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFolder == nil || music.isLoadingBilibiliFavoriteFolders || music.isImportingBilibiliFavoriteFolder)
            }
        }
        .padding(20)
        .frame(width: 540, height: 500)
        .interactiveDismissDisabled(music.isImportingBilibiliFavoriteFolder)
        .onAppear {
            if music.bilibiliFavoriteFolders.isEmpty { music.loadBilibiliFavoriteFolders() }
            else { selectedFolderID = music.bilibiliFavoriteFolders.first?.id }
        }
        .onChange(of: music.bilibiliFavoriteFolders) { _, folders in
            if selectedFolderID == nil || !folders.contains(where: { $0.id == selectedFolderID }) {
                selectedFolderID = folders.first?.id
            }
        }
    }

    private var selectedFolder: BilibiliFavoriteFolder? {
        guard let selectedFolderID else { return nil }
        return music.bilibiliFavoriteFolders.first { $0.id == selectedFolderID }
    }
}

struct BilibiliLoginSheet: View {
    @ObservedObject var music: MusicStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("哔哩哔哩账号", systemImage: "person.crop.circle")
                    .font(.title2.bold())
                Spacer()
            }

            if let account = music.bilibiliAccount {
                VStack(spacing: 10) {
                    AsyncImage(url: account.avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable().foregroundStyle(.secondary)
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    Text(account.name).font(.headline).textSelection(.enabled)
                    Text("UID \(account.mid)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("已登录，可读取账号有权访问的播放器字幕。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("退出账号", role: .destructive) { music.logoutBilibili() }
                    Spacer()
                    Button("完成") { isPresented = false }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Group {
                    if let value = music.bilibiliQRCodeURL, let image = qrImage(from: value) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 190, height: 190)
                            .padding(10)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if music.bilibiliLoginPhase == .requestingQRCode {
                        ProgressView("正在生成二维码…")
                            .frame(width: 210, height: 210)
                    } else {
                        Image(systemName: "qrcode")
                            .font(.system(size: 100, weight: .light))
                            .foregroundStyle(.secondary)
                            .frame(width: 210, height: 210)
                    }
                }

                Text(loginStatusText)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(loginStatusColor)
                Text("请使用哔哩哔哩手机客户端扫码并确认。YuanGUI 不会读取或保存账号密码。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack {
                    Button("取消") { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(music.bilibiliQRCodeURL == nil ? "生成二维码" : "刷新二维码") {
                        music.startBilibiliLogin()
                    }
                    .disabled(music.bilibiliLoginPhase == .requestingQRCode)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            if music.bilibiliAccount == nil,
               music.bilibiliLoginPhase != .requestingQRCode,
               music.bilibiliLoginPhase != .waitingForScan,
               music.bilibiliLoginPhase != .waitingForConfirmation {
                music.startBilibiliLogin()
            }
        }
        .onDisappear {
            if music.bilibiliAccount == nil { music.cancelBilibiliLogin() }
        }
    }

    private var loginStatusText: String {
        switch music.bilibiliLoginPhase {
        case .loggedOut: return "尚未登录"
        case .requestingQRCode: return "正在连接哔哩哔哩…"
        case .waitingForScan: return "等待扫码"
        case .waitingForConfirmation: return "已扫码，请在手机上确认"
        case .expired: return "二维码已失效，请刷新"
        case .loggedIn: return "登录成功"
        case .failed(let message): return message
        }
    }

    private var loginStatusColor: Color {
        switch music.bilibiliLoginPhase {
        case .failed, .expired: return .orange
        case .waitingForConfirmation: return .blue
        default: return .secondary
        }
    }

    private func qrImage(from value: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else {
            return nil
        }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

struct LyricOffsetControl: View {
    @ObservedObject var music: MusicStore
    var compact = false

    private var offset: Binding<Double> {
        Binding(get: { music.currentLyricOffset }, set: music.setLyricOffset)
    }

    var body: some View {
        HStack(spacing: compact ? 5 : 7) {
            Slider(value: offset, in: -30...30, step: 0.1)
                .frame(minWidth: compact ? 90 : 150, maxWidth: compact ? .infinity : 210)

            HStack(spacing: 3) {
                TextField(
                    "0.0",
                    value: offset,
                    format: .number.precision(.fractionLength(1...2))
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: compact ? 9 : 11, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .frame(width: compact ? 48 : 56)
                .help("直接输入 -30 到 30 秒，按回车确认")

                Text("秒")
                    .font(compact ? .system(size: 9) : .caption)
                    .foregroundStyle(.secondary)
            }

            Stepper("微调歌词偏移", value: offset, in: -30...30, step: 0.1)
                .labelsHidden()
                .controlSize(.mini)
                .help("每次微调 0.1 秒")

            if !compact {
                Button("归零") { music.setLyricOffset(0) }
                    .controlSize(.small)
                    .disabled(abs(music.currentLyricOffset) < 0.001)
            }
        }
        .disabled(music.currentTrack == nil)
    }
}

private struct LyricsSearchSheet: View {
    @ObservedObject var music: MusicStore
    @Binding var title: String
    @Binding var artist: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("修改歌曲信息或搜索歌词")
                .font(.title2.bold())
            Text("可以只保存歌曲名和歌手，不影响现有歌词；也可以保存信息后从 LRCLIB 匹配同步歌词。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Form {
                TextField("歌曲名", text: $title)
                TextField("歌手", text: $artist)
            }
            .formStyle(.grouped)
            if let message = music.lyricsSearchMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.hasPrefix("已") ? .green : .orange)
            }
            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("仅保存歌曲信息") {
                    if music.updateCurrentTrackMetadata(title: title, artist: artist) {
                        isPresented = false
                    }
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button {
                    music.searchLyrics(title: title, artist: artist)
                } label: {
                    if music.isSearchingLyrics { ProgressView().controlSize(.small) }
                    else { Text("匹配并更新") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(music.isSearchingLyrics || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 430)
    }
}

struct PetMusicLyricBubble: View {
    let text: String
    var alertText: String? = nil
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "music.note").foregroundStyle(.pink).font(.headline)
            Text(text).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(2)
            if let alertText {
                Label(alertText, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.orange.opacity(0.12), in: Capsule())
                    .fixedSize()
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.42), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .frame(maxWidth: 350)
    }
}

private func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "00:00" }
    return String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
}
