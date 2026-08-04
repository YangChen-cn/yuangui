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
    @ObservedObject var guide: PetGuideCoordinator
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
        guide: PetGuideCoordinator,
        presentation: PetAuxiliaryBubblePresentation
    ) {
        self.store = store
        self.chat = chat
        self.maintenance = maintenance
        self.focusTimer = focusTimer
        self.music = music
        self.guide = guide
        _playback = ObservedObject(wrappedValue: music.playback)
        _lyrics = ObservedObject(wrappedValue: music.lyricsStore)
        _lyricsPresentation = ObservedObject(wrappedValue: music.lyricsPresentation)
        self.presentation = presentation
    }

    /// Rendering, window sizing and visibility all derive from the same
    /// resolved kind (`PetAuxiliaryBubbleResolver`), so the SwiftUI content
    /// and the AppKit panel can never disagree about what is on screen.
    var body: some View {
        Group {
            switch resolvedKind {
            case .maintenance:
                PetMaintenanceBubble(
                    store: maintenance,
                    placement: presentation.placement
                )
            case .urgentStatus, .status:
                PetStatusBubble(store: store, placement: presentation.placement)
            case .guide:
                PetGuideBubbleView(
                    guide: guide,
                    placement: presentation.placement,
                    petScale: store.petScale
                )
            case .musicLyric:
                if let lyric = lyrics.currentLine?.text {
                    PetMusicLyricBubble(
                        text: lyricsPresentation.displayedText(lyric),
                        alertText: musicAlertText,
                        placement: presentation.placement
                    )
                }
            case .ambient:
                PetAmbientBubble(store: store, placement: presentation.placement)
            case .none:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color.clear)
    }

    private var resolvedKind: PetAuxiliaryBubbleKind {
        PetAuxiliaryBubbleResolver.resolve(
            hasMaintenanceTask: maintenance.quickMode != nil,
            urgentReminderVisible: store.urgentReminderVisible,
            activeGuide: guide.currentGuide,
            showsMusicLyric: showsMusicLyric,
            ambientMessageVisible: store.ambientMessage != nil,
            showsStatusBubble: store.shouldShowPetBubble
        )
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
