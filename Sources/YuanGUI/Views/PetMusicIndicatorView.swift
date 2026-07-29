import SwiftUI

struct PetMusicIndicatorView: View {
    @ObservedObject private var playback: MusicPlaybackStore
    @ObservedObject private var lyrics: LyricsStore
    @ObservedObject private var lyricsPresentation: LyricsPresentationStore

    let isChatPresented: Bool
    let hasMaintenanceTask: Bool
    let focusState: FocusTimerStore.State
    let scale: CGFloat

    init(
        music: MusicFeature,
        isChatPresented: Bool,
        hasMaintenanceTask: Bool,
        focusState: FocusTimerStore.State,
        scale: CGFloat
    ) {
        _playback = ObservedObject(wrappedValue: music.playback)
        _lyrics = ObservedObject(wrappedValue: music.lyricsStore)
        _lyricsPresentation = ObservedObject(wrappedValue: music.lyricsPresentation)
        self.isChatPresented = isChatPresented
        self.hasMaintenanceTask = hasMaintenanceTask
        self.focusState = focusState
        self.scale = scale
    }

    var body: some View {
        if showsIndicator {
            Image(systemName: "music.note")
                .font(.system(size: max(14, 24 * scale), weight: .bold))
                .foregroundStyle(.pink)
                .padding(6)
                .background(.regularMaterial, in: Circle())
                .symbolEffect(
                    .pulse,
                    options: .repeating.speed(0.35),
                    isActive: lyricsPresentation.lightSingAlongEnabled
                )
                .accessibilityLabel("音乐播放中")
        }
    }

    private var showsIndicator: Bool {
        let showsLyricBubble = PetMusicPresentationPolicy.showsLyricBubble(
            isPlaying: playback.isPlaying,
            lightSingAlongEnabled: lyricsPresentation.lightSingAlongEnabled,
            hasCurrentLyric: lyrics.currentLine != nil,
            isChatPresented: isChatPresented,
            hasMaintenanceTask: hasMaintenanceTask,
            focusState: focusState
        )
        return PetMusicPresentationPolicy.showsStandaloneMusicIndicator(
            isPlaying: playback.isPlaying,
            showsLyricBubble: showsLyricBubble
        )
    }
}
