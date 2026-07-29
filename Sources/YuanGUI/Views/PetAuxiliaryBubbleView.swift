import SwiftUI

@MainActor
final class PetAuxiliaryBubblePresentation: ObservableObject {
    @Published var placement: PetAuxiliaryBubblePlacement = .abovePet
    @Published var isVisible = false
}

struct PetAuxiliaryBubbleView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var chat: ChatStore
    @ObservedObject var maintenance: MaintenanceStore
    @ObservedObject var focusTimer: FocusTimerStore
    let music: MusicFeature
    @ObservedObject private var playback: MusicPlaybackStore
    @ObservedObject private var lyrics: LyricsStore
    @ObservedObject private var lyricsPresentation: LyricsPresentationStore
    @ObservedObject var presentation: PetAuxiliaryBubblePresentation

    init(
        store: PetStore,
        chat: ChatStore,
        maintenance: MaintenanceStore,
        focusTimer: FocusTimerStore,
        music: MusicFeature,
        presentation: PetAuxiliaryBubblePresentation
    ) {
        self.store = store
        self.chat = chat
        self.maintenance = maintenance
        self.focusTimer = focusTimer
        self.music = music
        _playback = ObservedObject(wrappedValue: music.playback)
        _lyrics = ObservedObject(wrappedValue: music.lyricsStore)
        _lyricsPresentation = ObservedObject(wrappedValue: music.lyricsPresentation)
        self.presentation = presentation
    }

    var body: some View {
        Group {
            if maintenance.quickMode != nil {
                PetMaintenanceBubble(
                    store: maintenance,
                    placement: presentation.placement
                )
            } else if showsMusicLyric, let lyric = lyrics.currentLine?.text {
                PetMusicLyricBubble(
                    text: lyric,
                    alertText: musicAlertText,
                    placement: presentation.placement
                )
            } else if store.ambientMessage != nil {
                PetAmbientBubble(store: store, placement: presentation.placement)
            } else if store.shouldShowPetBubble {
                PetStatusBubble(store: store, placement: presentation.placement)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color.clear)
    }

    private var showsMusicLyric: Bool {
        PetMusicPresentationPolicy.showsLyricBubble(
            isPlaying: playback.isPlaying,
            lightSingAlongEnabled: lyricsPresentation.lightSingAlongEnabled,
            hasCurrentLyric: lyrics.currentLine != nil,
            isChatPresented: chat.isPresented,
            hasMaintenanceTask: maintenance.quickMode != nil,
            focusState: focusTimer.state
        )
    }

    private var musicAlertText: String? {
        guard store.urgentReminderVisible else { return nil }
        switch store.smartState {
        case .lowBattery: return AppLocalizer.string("低电量")
        case .memoryPressure: return AppLocalizer.string("内存紧张")
        case .charging: return AppLocalizer.string("充电中")
        default: return nil
        }
    }
}
