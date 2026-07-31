import SwiftUI

struct DashboardHeaderContainer: View {
    @ObservedObject var store: PetStore
    @ObservedObject var focusTimer: FocusTimerStore
    @Binding var showsFocusPopover: Bool
    let showPet: () -> Void

    var body: some View {
        DashboardHeaderView(
            store: store,
            focusTimer: focusTimer,
            showsFocusPopover: $showsFocusPopover,
            showPet: showPet
        )
    }
}

struct DashboardPageContainer: View {
    let selection: DashboardSection
    let music: MusicFeature
    let externalAudioInterruption: ExternalAudioInterruptionController
    let quickTools: QuickToolsController
    let updater: AppUpdateStore
    let openSettings: () -> Void
    let dismiss: () -> Void
    let store: PetStore

    @ViewBuilder
    var body: some View {
        switch selection {
        case .overview:
            DashboardOverviewView(store: store)
        case .music:
            DashboardMusicView(
                music: music,
                externalAudioInterruption: externalAudioInterruption,
                dismiss: dismiss
            )
        case .tools:
            DashboardToolsView(
                quickTools: quickTools,
                updater: updater,
                openSettings: openSettings,
                dismiss: dismiss
            )
        }
    }
}

struct DashboardFooterContainer: View {
    @ObservedObject var store: PetStore
    let togglePet: () -> Void
    let showPet: () -> Void
    let openSettings: () -> Void
    let dismiss: () -> Void

    var body: some View {
        DashboardFooterView(
            store: store,
            togglePet: togglePet,
            showPet: showPet,
            openSettings: openSettings,
            dismiss: dismiss
        )
    }
}

struct DashboardAtmosphereContainer: View {
    @ObservedObject var store: PetStore

    var body: some View {
        DashboardAtmosphereBackground(
            palette: DashboardDesign.palette(for: store.dashboardStyle),
            mode: store.mode,
            smartState: store.smartState
        )
    }
}
