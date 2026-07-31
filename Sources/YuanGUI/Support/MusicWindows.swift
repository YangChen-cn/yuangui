import AppKit
import SwiftUI

private final class MusicPlayerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class MusicWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let onClose: () -> Void

    init(
        music: MusicFeature,
        appActions: AppActions = .disabled,
        onClose: @escaping () -> Void = {}
    ) {
        self.onClose = onClose
        window = MusicPlayerWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = AppLocalizer.string("音乐播放器")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 760, height: 520)
        window.contentView = NSHostingView(rootView:
            MusicPlayerView(music: music)
                .environment(\.appActions, appActions)
        )
        window.center()
    }

    func windowWillClose(_ notification: Notification) {
        window.contentView = nil
        window.delegate = nil
        onClose()
    }

    func show() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Activation of an accessory app and dismissal of its source panel can
        // finish one run-loop turn later. Reassert key/main status after that.
        DispatchQueue.main.async { [weak window] in
            guard let window, window.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeMain()
        }
    }
}

private final class LyricsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class LyricsLockedControlsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct LyricsLockedControlsView: View {
    let music: MusicFeature
    @ObservedObject private var lyricsPresentation: LyricsPresentationStore

    init(music: MusicFeature) {
        self.music = music
        _lyricsPresentation = ObservedObject(wrappedValue: music.lyricsPresentation)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                music.setLyricsPanelLocked(false)
            } label: {
                Image(systemName: "lock.fill")
            }
            .yuanSystemGlassButton()
            .controlSize(.small)
            .help("解锁桌面歌词")
            .accessibilityLabel("解锁桌面歌词")

            Button {
                music.toggleLyricsVisible()
            } label: {
                Image(systemName: "xmark")
            }
            .yuanSystemGlassButton()
            .controlSize(.small)
            .help("关闭桌面歌词")
            .accessibilityLabel("关闭桌面歌词")
        }
        .yuanGlassEffectContainer(spacing: 8)
        .padding(6)
    }
}

private struct DesktopLyricsView: View {
    let music: MusicFeature
    @ObservedObject private var playback: MusicPlaybackStore
    @ObservedObject private var lyrics: LyricsStore
    @ObservedObject private var lyricsPresentation: LyricsPresentationStore
    @State private var showsSettings = false
    @State private var searchTitle = ""
    @State private var searchArtist = ""

    init(music: MusicFeature) {
        self.music = music
        _playback = ObservedObject(wrappedValue: music.playback)
        _lyrics = ObservedObject(wrappedValue: music.lyricsStore)
        _lyricsPresentation = ObservedObject(wrappedValue: music.lyricsPresentation)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 2) {
                Text(
                    lyrics.currentLine?.text
                        ?? playback.currentTrack?.title
                        ?? AppLocalizer.string("YuanGUI 桌面歌词")
                )
                    .font(lyricsPresentation.fontStyle.font(
                        size: lyricsPresentation.fontSize,
                        weight: .bold
                    ))
                    .foregroundStyle(Color(nsColor: lyricsPresentation.color))
                    .shadow(
                        color: lyricsPresentation.shadowEnabled ? .black.opacity(0.38) : .clear,
                        radius: 1.5,
                        y: 1
                    )
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let next = lyrics.nextLine?.text {
                    Text(next).font(lyricsPresentation.fontStyle.font(
                        size: max(11, lyricsPresentation.fontSize * 0.52),
                        weight: .medium
                    ))
                        .foregroundStyle(Color(nsColor: lyricsPresentation.color).opacity(0.46))
                        .shadow(
                            color: lyricsPresentation.shadowEnabled ? .black.opacity(0.18) : .clear,
                            radius: 1,
                            y: 1
                        )
                        .lineLimit(1).minimumScaleFactor(0.65)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 72)

            if !lyricsPresentation.isPanelLocked {
                HStack(spacing: 5) {
                    Button {
                        music.toggleLyricsVisible()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .yuanSystemGlassButton()
                    .controlSize(.small)
                    .help("关闭桌面歌词")
                    .accessibilityLabel("关闭桌面歌词")

                    Button {
                        music.setLyricsPanelLocked(true)
                    } label: {
                        Image(systemName: "lock.open")
                    }
                    .yuanSystemGlassButton()
                    .controlSize(.small)
                    .help("锁定歌词并允许点击穿透；可从播放器解锁")
                    .accessibilityLabel("锁定桌面歌词")

                    Button {
                        syncSearchFields()
                        showsSettings.toggle()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .yuanSystemGlassButton()
                    .controlSize(.small)
                    .help("桌面歌词设置")
                    .accessibilityLabel("桌面歌词设置")
                    .popover(isPresented: $showsSettings, arrowEdge: .top) {
                        DesktopLyricsSettingsView(
                            music: music,
                            title: $searchTitle,
                            artist: $searchArtist
                        )
                    }
                }
                .yuanGlassEffectContainer(spacing: 5)
                .padding(6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(width: 620, height: 92)
        .background(
            Color.black.opacity(effectiveBackgroundOpacity),
            in: .rect(cornerRadius: 18)
        )
        .contentShape(.rect(cornerRadius: 18))
        .onAppear(perform: syncSearchFields)
        .onChange(of: playback.currentTrack?.id) { _, _ in syncSearchFields() }
    }

    private func syncSearchFields() {
        searchTitle = playback.currentTrack?.title ?? ""
        searchArtist = playback.currentTrack?.artist ?? ""
    }

    private var effectiveBackgroundOpacity: Double {
        min(
            lyricsPresentation.backgroundOpacity
                + (lyricsPresentation.backgroundVisible ? 0.10 : 0),
            0.70
        )
    }
}

private struct DesktopLyricsSettingsView: View {
    let music: MusicFeature
    @ObservedObject private var playback: MusicPlaybackStore
    @ObservedObject private var lyrics: LyricsStore
    @ObservedObject private var lyricsPresentation: LyricsPresentationStore
    @Binding var title: String
    @Binding var artist: String

    init(
        music: MusicFeature,
        title: Binding<String>,
        artist: Binding<String>
    ) {
        self.music = music
        _playback = ObservedObject(wrappedValue: music.playback)
        _lyrics = ObservedObject(wrappedValue: music.lyricsStore)
        _lyricsPresentation = ObservedObject(wrappedValue: music.lyricsPresentation)
        _title = title
        _artist = artist
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("桌面歌词设置")
                .font(.headline)
            HStack {
                Text("字号")
                Slider(
                    value: Binding(get: { lyricsPresentation.fontSize }, set: music.setLyricsFontSize),
                    in: 14...42,
                    step: 1
                )
                Text("\(Int(lyricsPresentation.fontSize))")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 26, alignment: .trailing)
            }
            HStack {
                Picker("字体", selection: Binding(
                    get: { lyricsPresentation.fontStyle },
                    set: music.setLyricsFontStyle
                )) {
                    ForEach(LyricsFontStyle.allCases) { style in Text(style.title).tag(style) }
                }
                .frame(width: 170)
                ColorPicker(
                    "文字颜色",
                    selection: Binding(
                        get: { Color(nsColor: lyricsPresentation.color) },
                        set: { music.setLyricsColor(NSColor($0)) }
                    ),
                    supportsOpacity: true
                )
            }
            Toggle("显示文字阴影", isOn: Binding(
                get: { lyricsPresentation.shadowEnabled },
                set: music.setLyricsShadowEnabled
            ))
            Toggle("增强歌词背景对比度", isOn: Binding(
                get: { lyricsPresentation.backgroundVisible },
                set: music.setLyricsBackgroundVisible
            ))
            HStack {
                Text("细条透明度")
                Slider(
                    value: Binding(
                        get: { lyricsPresentation.backgroundOpacity },
                        set: music.setLyricsBackgroundOpacity
                    ),
                    in: 0.12...0.60,
                    step: 0.01
                )
                Text(lyricsPresentation.backgroundOpacity, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 38, alignment: .trailing)
            }
            Divider()
            Text("歌词搜索信息")
                .font(.subheadline.weight(.semibold))
            TextField("歌曲名", text: $title)
            TextField("歌手", text: $artist)
            HStack {
                Button {
                    music.updateCurrentTrackMetadata(title: title, artist: artist)
                } label: {
                    Label("仅保存歌曲信息", systemImage: "square.and.arrow.down")
                }
                Button {
                    music.searchLyrics(title: title, artist: artist)
                } label: {
                    if lyrics.isSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("匹配歌词并更新信息", systemImage: "magnifyingglass")
                    }
                }
                .disabled(lyrics.isSearching || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let message = lyrics.searchMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text("歌词偏移")
                LyricOffsetControl(music: music, compact: true)
                Button("归零") { music.setLyricOffset(0) }
                    .controlSize(.small)
                    .disabled(abs(music.currentLyricOffset) < 0.001)
            }
            Text("正数延后，负数提前；按歌曲保存。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 380)
    }
}

private extension LyricsFontStyle {
    func font(size: CGFloat, weight: Font.Weight) -> Font {
        switch self {
        case .rounded:
            return .system(size: size, weight: weight, design: .rounded)
        case .system:
            return .system(size: size, weight: weight)
        case .serif:
            return .system(size: size, weight: weight, design: .serif)
        case .monospaced:
            return .system(size: size, weight: weight, design: .monospaced)
        case .pingFang:
            return .custom("PingFang SC", size: size).weight(weight)
        case .songti:
            return .custom("Songti SC", size: size).weight(weight)
        case .kaiti:
            return .custom("Kaiti SC", size: size).weight(weight)
        case .heiti:
            return .custom("Heiti SC", size: size).weight(weight)
        }
    }
}

@MainActor
final class LyricsPanelController {
    private let panel: LyricsPanel
    private let lockedControlsPanel: LyricsLockedControlsPanel
    private let music: MusicFeature
    private let defaults: UserDefaults
    private var moveObserver: NSObjectProtocol?
    private var lockedHoverFallbackTimer: DispatchSourceTimer?
    private var lockedControlsHideTask: Task<Void, Never>?
    private var wasPointerInsideLockedRegion = false

    init(music: MusicFeature, defaults: UserDefaults = .standard) {
        self.music = music
        self.defaults = defaults
        panel = LyricsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 92),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        lockedControlsPanel = LyricsLockedControlsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 82, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: DesktopLyricsView(music: music))
        panel.ignoresMouseEvents = music.lyricsPresentation.isPanelLocked
        lockedControlsPanel.isOpaque = false
        lockedControlsPanel.backgroundColor = .clear
        lockedControlsPanel.hasShadow = false
        lockedControlsPanel.level = .floating
        lockedControlsPanel.hidesOnDeactivate = false
        lockedControlsPanel.isReleasedWhenClosed = false
        lockedControlsPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        lockedControlsPanel.contentView = NSHostingView(rootView: LyricsLockedControlsView(music: music))
        restorePosition()
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.savePosition()
                self?.positionLockedControls()
            }
        }
    }

    func updateVisibility() { music.lyricsPresentation.isVisible ? show() : hide() }

    func updateLock() {
        panel.ignoresMouseEvents = music.lyricsPresentation.isPanelLocked
        if music.lyricsPresentation.isPanelLocked, panel.isVisible {
            startLockedHoverTracking()
        } else {
            stopLockedHoverTracking()
            lockedControlsPanel.orderOut(nil)
        }
    }

    func show() {
        panel.orderFrontRegardless()
        if music.lyricsPresentation.isPanelLocked { startLockedHoverTracking() }
    }

    func hide() {
        panel.orderOut(nil)
        lockedControlsPanel.orderOut(nil)
        stopLockedHoverTracking()
    }

    private func restorePosition() {
        if defaults.object(forKey: "musicLyricsPanelX") != nil {
            panel.setFrameOrigin(NSPoint(x: defaults.double(forKey: "musicLyricsPanelX"), y: defaults.double(forKey: "musicLyricsPanelY")))
        } else if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 310, y: screen.visibleFrame.minY + 95))
        }
    }
    private func savePosition() {
        defaults.set(panel.frame.minX, forKey: "musicLyricsPanelX")
        defaults.set(panel.frame.minY, forKey: "musicLyricsPanelY")
    }

    private func startLockedHoverTracking() {
        guard lockedHoverFallbackTimer == nil else {
            pollLockedPointer()
            return
        }
        wasPointerInsideLockedRegion = false
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(200), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in self?.pollLockedPointer() }
        lockedHoverFallbackTimer = timer
        timer.resume()
        pollLockedPointer()
    }

    private func stopLockedHoverTracking() {
        lockedHoverFallbackTimer?.cancel()
        lockedHoverFallbackTimer = nil
        lockedControlsHideTask?.cancel()
        lockedControlsHideTask = nil
        wasPointerInsideLockedRegion = false
    }

    private func pollLockedPointer() {
        guard music.lyricsPresentation.isPanelLocked, panel.isVisible else {
            stopLockedHoverTracking()
            lockedControlsPanel.orderOut(nil)
            return
        }
        let location = NSEvent.mouseLocation
        let inside = panel.frame.insetBy(dx: -6, dy: -6).contains(location)
            || lockedControlsPanel.frame.insetBy(dx: -6, dy: -6).contains(location)
        if inside {
            lockedControlsHideTask?.cancel()
            lockedControlsHideTask = nil
            positionLockedControls()
            if !lockedControlsPanel.isVisible { lockedControlsPanel.orderFrontRegardless() }
        } else if wasPointerInsideLockedRegion {
            scheduleLockedControlsHide()
        }
        wasPointerInsideLockedRegion = inside
    }

    private func scheduleLockedControlsHide() {
        lockedControlsHideTask?.cancel()
        lockedControlsHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.lockedControlsPanel.orderOut(nil)
            self.lockedControlsHideTask = nil
        }
    }

    private func positionLockedControls() {
        lockedControlsPanel.setFrameOrigin(NSPoint(
            x: panel.frame.maxX - lockedControlsPanel.frame.width - 12,
            y: panel.frame.maxY - lockedControlsPanel.frame.height - 10
        ))
    }
}
