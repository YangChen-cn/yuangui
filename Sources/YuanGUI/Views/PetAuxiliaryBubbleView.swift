import SwiftUI

struct PetAuxiliaryBubbleView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var chat: ChatStore
    @ObservedObject var maintenance: MaintenanceStore
    @ObservedObject var focusTimer: FocusTimerStore
    @ObservedMusicFeature var music: MusicFeature

    var body: some View {
        Group {
            if showsMusicLyric, let lyric = music.lyricsStore.currentLine?.text {
                PetMusicLyricBubble(text: lyric, alertText: musicAlertText)
            } else if store.ambientMessage != nil {
                PetAmbientBubble(store: store)
            } else if store.shouldShowPetBubble {
                PetStatusBubble(store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color.clear)
    }

    private var showsMusicLyric: Bool {
        music.playback.isPlaying && music.lyricsPresentation.lightSingAlongEnabled && music.lyricsStore.currentLine != nil
            && !chat.isPresented && maintenance.quickMode == nil
            && focusTimer.state != .running && focusTimer.state != .paused
    }

    private var musicAlertText: String? {
        guard store.urgentReminderVisible else { return nil }
        switch store.smartState {
        case .lowBattery: return "低电量"
        case .memoryPressure: return "内存紧张"
        case .charging: return "充电中"
        default: return nil
        }
    }
}
