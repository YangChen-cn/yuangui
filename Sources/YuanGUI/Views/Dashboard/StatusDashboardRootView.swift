import SwiftUI

struct StatusDashboardRootView: View {
    let store: PetStore
    let focusTimer: FocusTimerStore
    let music: MusicFeature
    let externalAudioInterruption: ExternalAudioInterruptionController
    let quickTools: QuickToolsController
    let panelState: DashboardPanelState
    let hostModel: DashboardHostModel
    let togglePet: () -> Void
    let showPet: () -> Void
    let openSettings: () -> Void
    let dismiss: () -> Void
    let layoutDidChange: (DashboardSection, MusicSource) -> Void
    let appActions: AppActions

    var body: some View {
        MenuBarDashboardView(
            store: store,
            focusTimer: focusTimer,
            music: music,
            externalAudioInterruption: externalAudioInterruption,
            quickTools: quickTools,
            panelState: panelState,
            hostModel: hostModel,
            togglePet: togglePet,
            showPet: showPet,
            openSettings: openSettings,
            dismiss: dismiss,
            layoutDidChange: layoutDidChange
        )
        .environment(\.appActions, appActions)
    }
}
