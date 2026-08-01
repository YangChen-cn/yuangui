import SwiftUI

struct StatusDashboardRootView: View {
    let store: PetStore
    let focusTimer: FocusTimerStore
    let music: MusicFeature
    let externalAudioInterruption: ExternalAudioInterruptionController
    let quickTools: QuickToolsController
    let panelState: DashboardPanelState
    @ObservedObject var hostModel: DashboardHostModel
    let updater: AppUpdateStore
    let togglePet: () -> Void
    let showPet: () -> Void
    let openSettings: () -> Void
    let dismiss: () -> Void
    let layoutDidChange: (DashboardSection, MusicSource) -> Void
    let appActions: AppActions

    var body: some View {
        Group {
            if hostModel.isPresented {
                MenuBarDashboardView(
                    width: hostModel.width,
                    maximumHeight: hostModel.maximumHeight,
                    store: store,
                    focusTimer: focusTimer,
                    music: music,
                    externalAudioInterruption: externalAudioInterruption,
                    quickTools: quickTools,
                    panelState: panelState,
                    updater: updater,
                    togglePet: togglePet,
                    showPet: showPet,
                    openSettings: openSettings,
                    dismiss: dismiss,
                    layoutDidChange: layoutDidChange
                )
            } else {
                Color.clear
            }
        }
        .environment(\.appActions, appActions)
        // This is an intentionally nonactivating menu-bar panel. Keep its
        // controls visually interactive without stealing focus from the app
        // whose selection may be used by Quick Tools.
        .environment(\.controlActiveState, .active)
    }
}
