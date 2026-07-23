import AppKit
import SwiftUI

private final class MusicPlayerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class MusicWindowController {
    private let window: NSWindow

    init(music: MusicFeature, appActions: AppActions = .disabled) {
        window = MusicPlayerWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "YuanGUI 音乐"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 520)
        window.contentView = NSHostingView(rootView:
            MusicPlayerView(music: music)
                .environment(\.appActions, appActions)
        )
        window.center()
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
    @ObservedMusicFeature var music: MusicFeature

    var body: some View {
        HStack(spacing: 8) {
            Button {
                music.setLyricsPanelLocked(false)
            } label: {
                Image(systemName: "lock.fill")
            }
            .help("解锁桌面歌词")

            Button {
                music.toggleLyricsVisible()
            } label: {
                Image(systemName: "xmark")
            }
            .help("关闭桌面歌词")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
    }
}

private struct DesktopLyricsView: View {
    @ObservedMusicFeature var music: MusicFeature
    @State private var showsSettings = false
    @State private var searchTitle = ""
    @State private var searchArtist = ""

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Text(music.lyricsStore.currentLine?.text ?? music.playback.currentTrack?.title ?? "YuanGUI 桌面歌词")
                    .font(.system(size: music.lyricsPresentation.fontSize, weight: .bold, design: music.lyricsPresentation.fontStyle.fontDesign))
                    .foregroundStyle(Color(nsColor: music.lyricsPresentation.color))
                    .shadow(
                        color: music.lyricsPresentation.shadowEnabled ? .black.opacity(0.9) : .clear,
                        radius: 3,
                        y: 1
                    )
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let next = music.lyricsStore.nextLine?.text {
                    Text(next).font(.system(size: max(12, music.lyricsPresentation.fontSize * 0.62), weight: .semibold, design: music.lyricsPresentation.fontStyle.fontDesign))
                        .foregroundStyle(Color(nsColor: music.lyricsPresentation.color).opacity(0.72))
                        .shadow(
                            color: music.lyricsPresentation.shadowEnabled ? .black.opacity(0.8) : .clear,
                            radius: 2,
                            y: 1
                        )
                        .lineLimit(1).minimumScaleFactor(0.65)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)

            if !music.lyricsPresentation.isPanelLocked {
                HStack(spacing: 5) {
                    Button {
                        music.toggleLyricsVisible()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("关闭桌面歌词")

                    Button {
                        music.setLyricsPanelLocked(true)
                    } label: {
                        Image(systemName: "lock.open")
                    }
                    .help("锁定歌词并允许点击穿透；可从播放器解锁")

                    Button {
                        syncSearchFields()
                        showsSettings.toggle()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .help("桌面歌词设置")
                    .popover(isPresented: $showsSettings, arrowEdge: .top) {
                        DesktopLyricsSettingsView(
                            music: music,
                            title: $searchTitle,
                            artist: $searchArtist
                        )
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(7)
                .background(.regularMaterial, in: Capsule())
                .padding(8)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 10)
        .frame(width: 620, height: 108)
        .background(
            music.lyricsPresentation.backgroundVisible ? Color.black.opacity(0.16) : Color.clear,
            in: Capsule()
        )
        .shadow(
            color: music.lyricsPresentation.backgroundVisible ? .black.opacity(0.24) : .clear,
            radius: 8,
            y: 4
        )
        .contentShape(Rectangle())
        .onAppear(perform: syncSearchFields)
        .onChange(of: music.playback.currentTrack?.id) { _, _ in syncSearchFields() }
    }

    private func syncSearchFields() {
        searchTitle = music.playback.currentTrack?.title ?? ""
        searchArtist = music.playback.currentTrack?.artist ?? ""
    }
}

private struct DesktopLyricsSettingsView: View {
    @ObservedMusicFeature var music: MusicFeature
    @Binding var title: String
    @Binding var artist: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("桌面歌词设置")
                .font(.headline)
            HStack {
                Text("字号")
                Slider(
                    value: Binding(get: { music.lyricsPresentation.fontSize }, set: music.setLyricsFontSize),
                    in: 14...42,
                    step: 1
                )
                Text("\(Int(music.lyricsPresentation.fontSize))")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 26, alignment: .trailing)
            }
            HStack {
                Picker("字体", selection: Binding(
                    get: { music.lyricsPresentation.fontStyle },
                    set: music.setLyricsFontStyle
                )) {
                    ForEach(LyricsFontStyle.allCases) { style in Text(style.title).tag(style) }
                }
                .frame(width: 170)
                ColorPicker(
                    "文字颜色",
                    selection: Binding(
                        get: { Color(nsColor: music.lyricsPresentation.color) },
                        set: { music.setLyricsColor(NSColor($0)) }
                    ),
                    supportsOpacity: true
                )
            }
            Toggle("显示文字阴影", isOn: Binding(
                get: { music.lyricsPresentation.shadowEnabled },
                set: music.setLyricsShadowEnabled
            ))
            Toggle("显示半透明背景长条", isOn: Binding(
                get: { music.lyricsPresentation.backgroundVisible },
                set: music.setLyricsBackgroundVisible
            ))
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
                    if music.lyricsStore.isSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("匹配歌词并更新信息", systemImage: "magnifyingglass")
                    }
                }
                .disabled(music.lyricsStore.isSearching || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let message = music.lyricsStore.searchMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.hasPrefix("已") ? Color.green : Color.orange)
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
    var fontDesign: Font.Design {
        switch self {
        case .rounded: return .rounded
        case .system: return .default
        case .serif: return .serif
        case .monospaced: return .monospaced
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
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 108),
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
