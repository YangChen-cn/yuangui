import Foundation

enum PetMusicPresentationPolicy {
    static func showsLyricBubble(
        isPlaying: Bool,
        lightSingAlongEnabled: Bool,
        hasCurrentLyric: Bool,
        isChatPresented: Bool,
        hasMaintenanceTask: Bool,
        focusState: FocusTimerStore.State
    ) -> Bool {
        isPlaying
            && lightSingAlongEnabled
            && hasCurrentLyric
            && !isChatPresented
            && !hasMaintenanceTask
            && focusState != .running
            && focusState != .paused
    }

    static func showsStandaloneMusicIndicator(
        isPlaying: Bool,
        showsLyricBubble: Bool
    ) -> Bool {
        isPlaying && !showsLyricBubble
    }
}
