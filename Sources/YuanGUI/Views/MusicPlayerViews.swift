import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

struct MusicArtworkView: View {
    let track: MusicTrack?
    var size: CGFloat = 54
    @State private var localArtwork: NSImage?

    var body: some View {
        Group {
            if let localArtwork {
                Image(nsImage: localArtwork).resizable().scaledToFill()
            } else if let url = displayCoverURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { placeholder }
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.18).stroke(.primary.opacity(0.12), lineWidth: 0.7))
        .task(id: track?.localArtworkCacheKey) {
            localArtwork = nil
            guard let track, track.localArtworkCacheKey != nil,
                  let data = await LocalMusicArtworkRepository.shared.data(for: track) else { return }
            localArtwork = NSImage(data: data)
        }
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
    @ObservedMusicFeature var music: MusicFeature
    var compact = false
    var usesGlassButtons = false

    var body: some View {
        HStack(spacing: compact ? 15 : 22) {
            Button(action: music.previous) { Image(systemName: "backward.fill") }
                .modifier(MusicTransportButtonModifier(usesGlass: usesGlassButtons))
                .help("上一首")
                .accessibilityLabel("上一首")
            Button(action: music.playPause) {
                Image(systemName: music.playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: compact ? 15 : 20, weight: .bold))
                    .frame(width: compact ? 27 : 38, height: compact ? 27 : 38)
                    .background(
                        usesGlassButtons ? Color.clear : Color.primary.opacity(0.10),
                        in: Circle()
                    )
            }
            .modifier(MusicTransportButtonModifier(usesGlass: usesGlassButtons))
            .help(AppLocalizer.string(music.playback.isPlaying ? "暂停" : "播放"))
            .accessibilityLabel(AppLocalizer.string(music.playback.isPlaying ? "暂停" : "播放"))
            Button(action: music.next) { Image(systemName: "forward.fill") }
                .modifier(MusicTransportButtonModifier(usesGlass: usesGlassButtons))
                .help("下一首")
                .accessibilityLabel("下一首")
        }
        .disabled(!music.canControl)
    }
}

private struct MusicTransportButtonModifier: ViewModifier {
    let usesGlass: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesGlass {
            content.yuanSystemGlassButton()
        } else {
            content.buttonStyle(.plain)
        }
    }
}

struct MusicProgressView: View {
    @ObservedMusicFeature var music: MusicFeature
    @ObservedObject private var progress: MusicPlaybackProgress
    @State private var previewPosition: TimeInterval = 0
    @State private var isSeeking = false

    init(music: MusicFeature) {
        _music = ObservedMusicFeature(wrappedValue: music)
        _progress = ObservedObject(wrappedValue: music.playback.progress)
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

struct MusicVolumeControl: View {
    @ObservedMusicFeature var music: MusicFeature
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 9) {
            Image(systemName: music.playback.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: compact ? 10 : 13))
                .foregroundStyle(.secondary)
            Slider(value: Binding(get: { music.playback.volume }, set: music.setVolume), in: 0...1)
                .controlSize(compact ? .mini : .regular)
                .accessibilityLabel("音量")
            Text("\(Int((music.playback.volume * 100).rounded()))%")
                .font(.system(size: compact ? 9 : 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: compact ? 28 : 34, alignment: .trailing)
        }
        .help("调整音量")
    }
}

private struct FullPlayerLyricsView: View {
    @ObservedMusicFeature var music: MusicFeature
    @State private var previewLyricPosition: Double?
    @State private var isScrollFocused = false
    @State private var resumeFollowingTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("歌词", systemImage: "quote.bubble")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let source = music.lyricsStore.document?.source, !source.isEmpty {
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
            isEnabled: music.lyricsStore.document?.lines.isEmpty == false,
            isActive: isScrollFocused,
            onActivationChange: setScrollFocus,
            onScroll: previewLyrics
        ))
        .help(AppLocalizer.string(isScrollFocused
            ? "歌词滚动已选中；点击播放器空白处退出，点击歌词可跳转"
            : "点击选中歌词区域，再上下滚动预览；点击歌词可跳转"))
        .onHover { isInside in
            if !isInside, isScrollFocused { setScrollFocus(false) }
        }
        .onDisappear { resumeFollowingTask?.cancel() }
    }

    @ViewBuilder
    private var lyricContent: some View {
        if music.playback.currentTrack == nil {
            lyricStatus("播放歌曲后显示歌词", systemImage: "music.note")
        } else if music.lyricsStore.isLoading {
            VStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("正在加载歌词").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 264)
        } else if let document = music.lyricsStore.document, !document.lines.isEmpty {
            lyricRows(document)
        } else {
            lyricStatus("暂无同步歌词", systemImage: "text.badge.xmark")
        }
    }

    private func lyricRows(_ document: LyricsDocument) -> some View {
        let currentPosition = previewLyricPosition ?? Double(music.lyricsStore.currentLineIndex ?? 0)
        let center = min(max(Int(currentPosition.rounded()), 0), document.lines.count - 1)
        let candidates = Array((center - 4)...(center + 4))
        let rowOffset = CGFloat(Double(center) - currentPosition) * 38
        return ZStack {
            VStack(spacing: 0) {
                ForEach(candidates, id: \.self) { lineIndex in
                    if document.lines.indices.contains(lineIndex) {
                        lyricButton(
                            document.lines[lineIndex],
                            isCurrent: lineIndex == music.lyricsStore.currentLineIndex,
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
        .help(AppLocalizer.format(
            "music.lyrics.jumpToTime",
            formatTime(line.time + music.currentLyricOffset)
        ))
        .accessibilityLabel(AppLocalizer.format(
            "music.lyrics.lineAccessibility",
            formatTime(line.time + music.currentLyricOffset),
            line.text
        ))
        .accessibilityHint("跳转到这句歌词")
    }

    private func lyricStatus(_ text: String, systemImage: String) -> some View {
        Label(AppLocalizer.string(text), systemImage: systemImage)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 264)
    }

    private func previewLyrics(_ delta: CGFloat) {
        guard let document = music.lyricsStore.document, !document.lines.isEmpty, abs(delta) > 0.01 else { return }
        let current = previewLyricPosition ?? Double(music.lyricsStore.currentLineIndex ?? 0)
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
    @ObservedMusicFeature var music: MusicFeature
    @Environment(\.appActions) private var appActions
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MusicArtworkView(track: music.playback.currentTrack, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(music.playback.currentTrack?.title ?? AppLocalizer.string("暂无播放内容"))
                        .font(.headline)
                        .lineLimit(1)
                    Text(music.playback.currentTrack?.artist ?? music.playback.playbackSource.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Label(music.playback.playbackSource.title, systemImage: music.playback.playbackSource.systemImage)
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            MusicProgressView(music: music)
            HStack {
                Button { music.toggleLyricsVisible() } label: {
                    Image(systemName: music.lyricsPresentation.isVisible ? "quote.bubble.fill" : "quote.bubble")
                }
                .yuanSystemGlassButton()
                .controlSize(.small)
                .help(AppLocalizer.string(
                    music.lyricsPresentation.isVisible ? "隐藏桌面歌词" : "显示桌面歌词"
                ))
                .accessibilityLabel(AppLocalizer.string(
                    music.lyricsPresentation.isVisible ? "隐藏桌面歌词" : "显示桌面歌词"
                ))
                Button { music.setLyricsPanelLocked(!music.lyricsPresentation.isPanelLocked) } label: {
                    Image(systemName: music.lyricsPresentation.isPanelLocked ? "lock.fill" : "lock.open")
                }
                .yuanSystemGlassButton()
                .controlSize(.small)
                .help(AppLocalizer.string(
                    music.lyricsPresentation.isPanelLocked ? "解锁桌面歌词" : "锁定桌面歌词"
                ))
                .accessibilityLabel(AppLocalizer.string(
                    music.lyricsPresentation.isPanelLocked ? "解锁桌面歌词" : "锁定桌面歌词"
                ))
                Spacer()
                MusicTransportControls(music: music, compact: true, usesGlassButtons: true)
                Spacer()
                Button { appActions.open(.music) } label: { Image(systemName: "list.bullet") }
                    .yuanSystemGlassButton()
                    .controlSize(.small)
                    .help("打开完整播放器")
                    .accessibilityLabel("打开完整播放器")
            }
        }
        .padding(12)
        .frame(width: 300)
        .yuanLiquidGlassSurface(.regular, cornerRadius: 22)
        .padding(6)
        .presentationBackground(.clear)
    }
}

struct MusicPlayerView: View {
    @ObservedMusicFeature var music: MusicFeature
    @State private var selectedTrackID: String?
    @State private var selectedCollectionID = "all"
    @State private var isCreatingPlaylist = false
    @State private var newPlaylistName = ""
    @State private var isSearchingLyrics = false
    @State private var isBilibiliLoginPresented = false
    @State private var isBilibiliFavoritesPresented = false
    @State private var isLocalImportFailuresPresented = false
    @State private var lyricsSearchTitle = ""
    @State private var lyricsSearchArtist = ""
    @State private var librarySearchText = ""
    @State private var librarySortField: MusicLibraryQuery.SortField = .libraryOrder
    @State private var librarySortDirection: MusicLibraryQuery.SortDirection = .ascending

    var body: some View {
        VStack(spacing: 0) {
            Picker("浏览来源", selection: Binding(get: { music.playback.source }, set: music.setSource)) {
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
        .onAppear { selectedTrackID = music.playback.currentTrack?.id }
        .onChange(of: music.playback.currentTrack?.id) { _, currentTrackID in
            selectedTrackID = currentTrackID
        }
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
        .sheet(isPresented: $isLocalImportFailuresPresented) {
            LocalMusicImportFailureSheet(
                failures: music.localImportStore.failures,
                isPresented: $isLocalImportFailuresPresented
            )
        }
    }

    @ViewBuilder private var sidebar: some View {
        if music.playback.source == .appleMusic {
            List {
                Section("Apple Music") {
                    Label(
                        AppLocalizer.string(
                            music.playback.appleMusicRunning ? "Music 正在运行" : "Music 尚未运行"
                        ),
                        systemImage: "music.note"
                    )
                    Button("连接并控制 Music App") { music.connectAppleMusic() }
                    Button("打开 Music App") { music.openAppleMusic() }
                }
            }.listStyle(.sidebar)
        } else if music.playback.source == .local {
            localSidebar
        } else {
            VStack(spacing: 0) {
                HStack {
                    TextField(
                        "粘贴 URL 或输入 BV 号",
                        text: Binding(
                            get: { music.bilibiliImportStore.input },
                            set: { music.bilibiliImportStore.input = $0 }
                        )
                    )
                        .onSubmit(music.importBilibili)
                    Button { music.importBilibili() } label: {
                        music.bilibiliImportStore.isImporting ? AnyView(ProgressView().controlSize(.small)) : AnyView(Image(systemName: "plus"))
                    }.disabled(music.bilibiliImportStore.isImporting || music.bilibiliImportStore.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(10)
                if let message = music.bilibiliImportStore.importMessage {
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
                libraryFilterBar
                HStack {
                    Button {
                        if music.bilibiliAccountStore.account == nil { isBilibiliLoginPresented = true }
                        else { isBilibiliFavoritesPresented = true }
                    } label: {
                        Label(
                            AppLocalizer.string(
                                music.bilibiliAccountStore.account == nil
                                    ? "登录后导入收藏夹"
                                    : "导入哔哩哔哩收藏夹"
                            ),
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
                        collectionButton("播放列表", systemImage: "music.note.list", id: "all", count: bilibiliTracks.count)
                        collectionButton(
                            "收藏",
                            systemImage: "heart.fill",
                            id: "favorites",
                            count: bilibiliTracks.count(where: music.isFavorite)
                        )
                    }
                    Section {
                        ForEach(music.libraryStore.savedPlaylists) { savedPlaylist in
                            collectionButton(
                                savedPlaylist.name,
                                systemImage: "music.note.house",
                                id: "playlist:\(savedPlaylist.id.uuidString)",
                                count: music.tracks(in: savedPlaylist).count(where: { $0.source == .bilibili }),
                                localizesTitle: false
                            )
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
                            Image(systemName: music.playback.currentTrack?.id == track.id && music.playback.isPlaying ? "speaker.wave.2.fill" : "music.note")
                                .foregroundStyle(music.playback.currentTrack?.id == track.id ? .pink : .secondary).frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title).lineLimit(1)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .tag(track.id)
                        .contextMenu {
                            Button("播放") { music.play(track) }
                            Button(AppLocalizer.string(music.isFavorite(track) ? "取消收藏" : "收藏")) {
                                music.toggleFavorite(track)
                            }
                            if !music.libraryStore.savedPlaylists.isEmpty {
                                Menu("加入歌单") {
                                    ForEach(music.libraryStore.savedPlaylists) { savedPlaylist in
                                        Button(savedPlaylist.name) { music.add(track, to: savedPlaylist) }
                                    }
                                }
                            }
                            if let selectedSavedPlaylist {
                                Button("从此歌单移除") { music.remove(track, from: selectedSavedPlaylist) }
                            }
                            Button("music.artwork.choose") { chooseArtwork(for: track) }
                            if track.localArtworkCacheKey != nil {
                                Button("music.artwork.remove") { music.removeArtwork(for: track) }
                            }
                            Button("从资料库移除", role: .destructive) { music.remove(track) }
                        }
                        .onTapGesture(count: 2) { music.play(track) }
                    }
                    }
                }
                .listStyle(.sidebar)
                .overlay {
                    if displayedTracks.isEmpty, !librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView.search
                    }
                }
                HStack {
                    Text(AppLocalizer.format("music.library.trackCount", displayedTracks.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if selectedCollectionID == "all",
                       librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !displayedTracks.isEmpty {
                        Button("清空") { music.clearPlaylist() }.buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }.padding(10)
            }
        }
    }

    private var localSidebar: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    localImportFileButton
                    localImportFolderButton
                    localImportProgress
                }
                VStack(alignment: .leading, spacing: 8) {
                    localImportFileButton
                    localImportFolderButton
                    localImportProgress
                }
            }
            .padding(10)
            if let message = music.localImportStore.message {
                HStack(spacing: 8) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !music.localImportStore.failures.isEmpty {
                        Button(AppLocalizer.string("music.local.import.failures.show")) {
                            isLocalImportFailuresPresented = true
                        }
                        .buttonStyle(.link)
                        .controlSize(.small)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
            }
            if localTracks.isEmpty {
                ContentUnavailableView {
                    Label("music.local.empty.title", systemImage: "music.note.house")
                } description: {
                    VStack(spacing: 3) {
                        Text("music.local.empty.description")
                        Text("music.local.empty.privacy")
                    }
                } actions: {
                    Button("music.local.import.action", action: chooseLocalFiles)
                }
                .frame(maxHeight: .infinity)
            } else {
                libraryFilterBar
                List(selection: $selectedTrackID) {
                    Section("资料库") {
                        collectionButton("播放列表", systemImage: "music.note.list", id: "all", count: localTracks.count)
                        collectionButton(
                            "收藏",
                            systemImage: "heart.fill",
                            id: "favorites",
                            count: localTracks.count(where: music.isFavorite)
                        )
                    }
                    Section {
                        ForEach(music.libraryStore.savedPlaylists) { savedPlaylist in
                            collectionButton(
                                savedPlaylist.name,
                                systemImage: "music.note.house",
                                id: "playlist:\(savedPlaylist.id.uuidString)",
                                count: music.tracks(in: savedPlaylist).count(where: { $0.source == .local }),
                                localizesTitle: false
                            )
                        }
                        Button { isCreatingPlaylist = true } label: { Label("新建歌单", systemImage: "plus") }
                    } header: { Text("我的歌单") }
                    Section(collectionTitle) {
                        ForEach(displayedTracks) { track in
                            HStack(spacing: 8) {
                                Image(systemName: music.playback.currentTrack?.id == track.id && music.playback.isPlaying
                                    ? "speaker.wave.2.fill"
                                    : "music.note")
                                    .foregroundStyle(music.playback.currentTrack?.id == track.id ? .pink : .secondary)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title).lineLimit(1)
                                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    if let filename = track.local?.originalFilename {
                                        Text(filename).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                    }
                                }
                            }
                            .tag(track.id)
                            .contextMenu {
                                Button("播放") { music.play(track) }
                                Button(AppLocalizer.string(music.isFavorite(track) ? "取消收藏" : "收藏")) {
                                    music.toggleFavorite(track)
                                }
                                Menu("加入歌单") {
                                    ForEach(music.libraryStore.savedPlaylists) { savedPlaylist in
                                        Button(savedPlaylist.name) { music.add(track, to: savedPlaylist) }
                                    }
                                }
                                Button("music.local.relocate") { chooseRelocation(for: track) }
                                Button("music.local.revealInFinder") { music.revealInFinder(track) }
                                Button("music.artwork.choose") { chooseArtwork(for: track) }
                                if track.localArtworkCacheKey != nil {
                                    Button("music.artwork.remove") { music.removeArtwork(for: track) }
                                }
                                Button("从资料库移除", role: .destructive) { music.remove(track) }
                            }
                            .onTapGesture(count: 2) { music.play(track) }
                        }
                    }
                }
                .listStyle(.sidebar)
                .overlay {
                    if displayedTracks.isEmpty, !librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView.search
                    }
                }
            }
        }
    }

    private var detail: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack(alignment: .topTrailing) {
                    MusicArtworkView(track: music.playback.currentTrack, size: 190)
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                        .frame(maxWidth: .infinity)
                    if music.playback.source == .bilibili {
                        bilibiliAccountButton
                    }
                }
                VStack(spacing: 4) {
                    Text(music.playback.currentTrack?.title ?? emptyTitle).font(.system(size: 24, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                    Text(music.playback.currentTrack?.artist ?? music.playback.playbackSource.title).foregroundStyle(.secondary)
                    if let album = music.playback.currentTrack?.album, !album.isEmpty { Text(album).font(.caption).foregroundStyle(.tertiary) }
                }
                MusicProgressView(music: music).frame(maxWidth: 480)
                MusicTransportControls(music: music)
                if let track = music.playback.currentTrack, track.source != .appleMusic {
                    HStack(spacing: 8) {
                        Button { music.toggleFavorite(track) } label: {
                            Label(
                                AppLocalizer.string(music.isFavorite(track) ? "已收藏" : "收藏"),
                                systemImage: music.isFavorite(track) ? "heart.fill" : "heart"
                            )
                        }
                        .buttonStyle(.bordered)
                        .tint(.pink)

                        Menu("music.artwork.menu", systemImage: "photo") {
                            Button("music.artwork.choose") { chooseArtwork(for: track) }
                            if track.localArtworkCacheKey != nil {
                                Button("music.artwork.remove", role: .destructive) {
                                    music.removeArtwork(for: track)
                                }
                            }
                        }
                        .menuStyle(.button)
                    }
                }
                MusicVolumeControl(music: music).frame(width: 230)
                if music.playback.source != .appleMusic {
                    Picker("播放模式", selection: Binding(get: { music.playback.playMode }, set: music.setPlayMode)) {
                        ForEach(MusicPlayMode.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }.labelsHidden().frame(width: 120)
                }
                FullPlayerLyricsView(music: music)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { lyricsActionButtons }
                    VStack(alignment: .leading, spacing: 7) { lyricsActionButtons }
                }
                lyricsAdjustments
                if let error = music.bilibiliImportStore.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                    if music.playback.playbackSource == .appleMusic { Button("打开自动化权限设置") { music.openAutomationSettings() } }
                }
                if let error = music.localImportStore.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                    if let track = music.localImportStore.trackNeedingRelocation {
                        HStack {
                            Button("music.local.relocate") { chooseRelocation(for: track) }
                            Button("music.local.remove", role: .destructive) { music.remove(track) }
                        }
                    }
                }
            }
            .padding(28).frame(maxWidth: .infinity)
        }
    }

    private var bilibiliAccountButton: some View {
        Button { isBilibiliLoginPresented = true } label: {
            HStack(spacing: 7) {
                if let account = music.bilibiliAccountStore.account {
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
            .frame(width: music.bilibiliAccountStore.account == nil ? 148 : 175, alignment: .leading)
            .frame(minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .fixedSize(horizontal: true, vertical: true)
        .offset(x: music.bilibiliAccountStore.account == nil ? 0 : 20)
        .help(music.bilibiliAccountStore.account.map {
            AppLocalizer.format("music.bilibili.account.manage", $0.name)
        } ?? AppLocalizer.string("扫码登录哔哩哔哩"))
    }

    private var emptyTitle: String {
        switch music.playback.source {
        case .appleMusic: AppLocalizer.string("连接 Apple Music")
        case .local: AppLocalizer.string("music.local.empty.title")
        case .bilibili: AppLocalizer.string("从左侧导入并选择歌曲")
        }
    }

    @ViewBuilder
    private var lyricsActionButtons: some View {
        Button(AppLocalizer.string(
            music.lyricsPresentation.isVisible ? "隐藏桌面歌词" : "显示桌面歌词"
        )) {
            music.toggleLyricsVisible()
        }
        Button("导入 LRC 文件") { chooseLRC() }
        Button("修改歌曲信息或匹配歌词") { prepareLyricsSearch() }
    }

    private var lyricsAdjustments: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(AppLocalizer.string("歌词偏移"))
                    .font(.headline)
                LyricOffsetControl(music: music)
            }
            Text("正数会让歌词延后出现，负数会让歌词提前出现。偏移按歌曲保存。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Label(AppLocalizer.string("桌面歌词字号"), systemImage: "textformat.size")
                    .font(.headline)

                HStack(spacing: 10) {
                    Slider(
                        value: Binding(get: { music.lyricsPresentation.fontSize }, set: music.setLyricsFontSize),
                        in: 14...42,
                        step: 1
                    )
                    .frame(maxWidth: .infinity)
                    Text("\(Int(music.lyricsPresentation.fontSize))")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 28, alignment: .trailing)
                }

                HStack(spacing: 12) {
                    Picker(AppLocalizer.string("字体"), selection: Binding(
                        get: { music.lyricsPresentation.fontStyle },
                        set: music.setLyricsFontStyle
                    )) {
                        ForEach(LyricsFontStyle.allCases) { style in Text(style.title).tag(style) }
                    }
                    .frame(maxWidth: 260)

                    ColorPicker(
                        AppLocalizer.string("颜色"),
                        selection: Binding(
                            get: { Color(nsColor: music.lyricsPresentation.color) },
                            set: { music.setLyricsColor(NSColor($0)) }
                        ),
                        supportsOpacity: true
                    )
                    .fixedSize()
                }

                Toggle(AppLocalizer.string("锁定并点击穿透"), isOn: Binding(
                    get: { music.lyricsPresentation.isPanelLocked },
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
        return music.libraryStore.savedPlaylists.first { $0.id == id }
    }

    private var displayedTracks: [MusicTrack] {
        let tracks: [MusicTrack]
        if selectedCollectionID == "favorites" { tracks = music.libraryStore.favoriteTracks }
        else if let selectedSavedPlaylist { tracks = music.tracks(in: selectedSavedPlaylist) }
        else { tracks = music.libraryStore.playlist }
        return MusicLibraryQuery(
            searchText: librarySearchText,
            sortField: librarySortField,
            sortDirection: librarySortDirection
        ).apply(to: tracks.filter { $0.source == music.playback.source })
    }

    private var libraryFilterBar: some View {
        MusicLibraryFilterBar(
            searchText: $librarySearchText,
            sortField: $librarySortField,
            sortDirection: $librarySortDirection
        )
    }

    private var collectionTitle: String {
        if selectedCollectionID == "favorites" { return AppLocalizer.string("收藏歌曲") }
        return selectedSavedPlaylist?.name ?? AppLocalizer.string("播放列表")
    }

    private func collectionButton(
        _ title: String,
        systemImage: String,
        id: String,
        count: Int,
        localizesTitle: Bool = true
    ) -> some View {
        Button { selectedCollectionID = id } label: {
            HStack {
                Label {
                    if localizesTitle {
                        Text(AppLocalizer.string(title))
                    } else {
                        Text(verbatim: title)
                    }
                } icon: {
                    Image(systemName: systemImage)
                }
                .lineLimit(1)
                Spacer()
                Text("\(count)").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedCollectionID == id ? Color.accentColor : Color.primary)
    }

    private var localImportFileButton: some View {
        Button("music.local.import.files", systemImage: "plus", action: chooseLocalFiles)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var localImportFolderButton: some View {
        Button("music.local.import.folder", systemImage: "folder.badge.plus", action: chooseLocalFolder)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var localImportProgress: some View {
        if music.localImportStore.isImporting {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Button("取消", action: music.cancelLocalImport)
            }
        }
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

    private var localTracks: [MusicTrack] {
        music.libraryStore.playlist.filter { $0.source == .local }
    }

    private var bilibiliTracks: [MusicTrack] {
        music.libraryStore.playlist.filter { $0.source == .bilibili }
    }

    private func chooseLocalFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = LocalMusicImportService.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        if panel.runModal() == .OK { music.importLocalMusic(panel.urls) }
    }

    private func chooseLocalFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { music.importLocalMusic(panel.urls) }
    }

    private func chooseRelocation(for track: MusicTrack) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = LocalMusicImportService.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.nameFieldStringValue = track.local?.originalFilename ?? ""
        if panel.runModal() == .OK, let url = panel.url { music.relocate(track, to: url) }
    }

    private func chooseArtwork(for track: MusicTrack) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = AppLocalizer.string("music.artwork.chooseButton")
        if panel.runModal() == .OK, let url = panel.url {
            music.setArtwork(for: track, from: url)
        }
    }

    private func prepareLyricsSearch() {
        lyricsSearchTitle = music.playback.currentTrack?.title ?? ""
        lyricsSearchArtist = music.playback.currentTrack?.artist ?? ""
        isSearchingLyrics = true
    }
}

struct BilibiliFavoriteImportSheet: View {
    @ObservedMusicFeature var music: MusicFeature
    @Binding var isPresented: Bool
    @State private var selectedFolderID: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("导入哔哩哔哩收藏夹", systemImage: "folder.badge.plus")
                    .font(.title2.bold())
                Spacer()
                if let account = music.bilibiliAccountStore.account {
                    Text(account.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text("选择一个收藏夹后，YuanGUI 会去重加入播放列表，并创建或更新同名本地歌单。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if music.bilibiliImportStore.isLoadingFavoriteFolders {
                ProgressView("正在读取收藏夹…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if music.bilibiliImportStore.favoriteFolders.isEmpty {
                ContentUnavailableView(
                    "没有可导入的收藏夹",
                    systemImage: "folder",
                    description: Text(
                        music.bilibiliImportStore.favoriteMessage
                            ?? AppLocalizer.string("请确认账号已登录，并尝试刷新。")
                    )
                )
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $selectedFolderID) {
                    ForEach(BilibiliFavoriteFolderKind.allCases, id: \.self) { kind in
                        let folders = music.bilibiliImportStore.favoriteFolders.filter { $0.kind == kind }
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
                                                Text(AppLocalizer.format(
                                                    "music.bilibili.videoCount",
                                                    folder.mediaCount
                                                ))
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

            if music.bilibiliImportStore.isImportingFavoriteFolder {
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(
                        value: Double(music.bilibiliImportStore.completedCount),
                        total: Double(max(music.bilibiliImportStore.totalCount, 1))
                    )
                    Text(AppLocalizer.format(
                        "music.bilibili.importProgress",
                        music.bilibiliImportStore.completedCount,
                        music.bilibiliImportStore.totalCount
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let message = music.bilibiliImportStore.favoriteMessage,
                      !music.bilibiliImportStore.favoriteFolders.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("刷新") { music.loadBilibiliFavoriteFolders() }
                    .disabled(music.bilibiliImportStore.isLoadingFavoriteFolders || music.bilibiliImportStore.isImportingFavoriteFolder)
                Spacer()
                Button("完成") { isPresented = false }
                    .disabled(music.bilibiliImportStore.isImportingFavoriteFolder)
                Button("一键导入") {
                    if let selectedFolder { music.importBilibiliFavoriteFolder(selectedFolder) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFolder == nil || music.bilibiliImportStore.isLoadingFavoriteFolders || music.bilibiliImportStore.isImportingFavoriteFolder)
            }
        }
        .padding(20)
        .frame(width: 540, height: 500)
        .interactiveDismissDisabled(music.bilibiliImportStore.isImportingFavoriteFolder)
        .onAppear {
            if music.bilibiliImportStore.favoriteFolders.isEmpty { music.loadBilibiliFavoriteFolders() }
            else { selectedFolderID = music.bilibiliImportStore.favoriteFolders.first?.id }
        }
        .onChange(of: music.bilibiliImportStore.favoriteFolders) { _, folders in
            if selectedFolderID == nil || !folders.contains(where: { $0.id == selectedFolderID }) {
                selectedFolderID = folders.first?.id
            }
        }
    }

    private var selectedFolder: BilibiliFavoriteFolder? {
        guard let selectedFolderID else { return nil }
        return music.bilibiliImportStore.favoriteFolders.first { $0.id == selectedFolderID }
    }
}

struct BilibiliLoginSheet: View {
    @ObservedMusicFeature var music: MusicFeature
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("哔哩哔哩账号", systemImage: "person.crop.circle")
                    .font(.title2.bold())
                Spacer()
            }

            if let account = music.bilibiliAccountStore.account {
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
                    if let value = music.bilibiliAccountStore.qrCodeURL, let image = qrImage(from: value) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 190, height: 190)
                            .padding(10)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if music.bilibiliAccountStore.loginPhase == .requestingQRCode {
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
                    Button(AppLocalizer.string(
                        music.bilibiliAccountStore.qrCodeURL == nil ? "生成二维码" : "刷新二维码"
                    )) {
                        music.startBilibiliLogin()
                    }
                    .disabled(music.bilibiliAccountStore.loginPhase == .requestingQRCode)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            if music.bilibiliAccountStore.account == nil,
               music.bilibiliAccountStore.loginPhase != .requestingQRCode,
               music.bilibiliAccountStore.loginPhase != .waitingForScan,
               music.bilibiliAccountStore.loginPhase != .waitingForConfirmation {
                music.startBilibiliLogin()
            }
        }
        .onDisappear {
            if music.bilibiliAccountStore.account == nil { music.cancelBilibiliLogin() }
        }
    }

    private var loginStatusText: String {
        switch music.bilibiliAccountStore.loginPhase {
        case .loggedOut: return AppLocalizer.string("尚未登录")
        case .requestingQRCode: return AppLocalizer.string("正在连接哔哩哔哩…")
        case .waitingForScan: return AppLocalizer.string("等待扫码")
        case .waitingForConfirmation: return AppLocalizer.string("已扫码，请在手机上确认")
        case .expired: return AppLocalizer.string("二维码已失效，请刷新")
        case .loggedIn: return AppLocalizer.string("登录成功")
        case .failed(let message): return AppLocalizer.string(message)
        }
    }

    private var loginStatusColor: Color {
        switch music.bilibiliAccountStore.loginPhase {
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
    @ObservedMusicFeature var music: MusicFeature
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
        .disabled(music.playback.currentTrack == nil)
    }
}

private struct LyricsSearchSheet: View {
    @ObservedMusicFeature var music: MusicFeature
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
            if let message = music.lyricsStore.searchMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    if music.lyricsStore.isSearching { ProgressView().controlSize(.small) }
                    else { Text("匹配并更新") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(music.lyricsStore.isSearching || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 430)
    }
}

struct PetMusicLyricBubble: View {
    let text: String
    var alertText: String? = nil
    var placement: PetAuxiliaryBubblePlacement = .abovePet

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "music.note")
                .foregroundStyle(.pink)
                .font(.headline)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: 350)
        .fixedSize(horizontal: false, vertical: true)
        .yuanPetBubbleGlass(
            cornerRadius: 20,
            placement: placement,
            tailWidth: 20,
            tailHeight: 10,
            tailOffset: 8
        )
    }
}

private func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "00:00" }
    return String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
}
