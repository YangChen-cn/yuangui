import SwiftUI

struct MenuBarDashboardView: View {
    static let preferredWidth = DashboardDesign.preferredWidth

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

    var body: some View {
        DashboardContentRoot(
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
    }
}

private struct DashboardContentRoot: View {
    static let preferredWidth = DashboardDesign.preferredWidth

    @ObservedObject var store: PetStore
    @ObservedObject var focusTimer: FocusTimerStore
    let music: MusicFeature
    @ObservedObject private var playback: MusicPlaybackStore
    @ObservedObject var externalAudioInterruption: ExternalAudioInterruptionController
    @ObservedObject var quickTools: QuickToolsController
    @ObservedObject var panelState: DashboardPanelState
    @ObservedObject var hostModel: DashboardHostModel
    let togglePet: () -> Void
    let showPet: () -> Void
    let openSettings: () -> Void
    let dismiss: () -> Void
    let layoutDidChange: (DashboardSection, MusicSource) -> Void

    @Environment(\.appActions) private var appActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var updater = AppUpdateStore()
    @State private var showsFocusPopover = false

    init(
        store: PetStore,
        focusTimer: FocusTimerStore,
        music: MusicFeature,
        externalAudioInterruption: ExternalAudioInterruptionController,
        quickTools: QuickToolsController,
        panelState: DashboardPanelState,
        hostModel: DashboardHostModel,
        togglePet: @escaping () -> Void,
        showPet: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        dismiss: @escaping () -> Void,
        layoutDidChange: @escaping (DashboardSection, MusicSource) -> Void
    ) {
        self.store = store
        self.focusTimer = focusTimer
        self.music = music
        _playback = ObservedObject(wrappedValue: music.playback)
        self.externalAudioInterruption = externalAudioInterruption
        self.quickTools = quickTools
        self.panelState = panelState
        self.hostModel = hostModel
        self.togglePet = togglePet
        self.showPet = showPet
        self.openSettings = openSettings
        self.dismiss = dismiss
        self.layoutDidChange = layoutDidChange
    }

    private var palette: DashboardPalette {
        DashboardDesign.palette(for: store.dashboardStyle)
    }

    var body: some View {
        VStack(spacing: DashboardDesign.sectionSpacing) {
            DashboardHeaderContainer(
                store: store,
                focusTimer: focusTimer,
                showsFocusPopover: $showsFocusPopover,
                showPet: showPet
            )
            DashboardSectionPicker(selection: $panelState.selectedSection)
            DashboardPageContainer(
                selection: panelState.selectedSection,
                music: music,
                externalAudioInterruption: externalAudioInterruption,
                quickTools: quickTools,
                updater: updater,
                openSettings: openSettings,
                dismiss: dismiss,
                store: store
            )
                .frame(maxWidth: .infinity, alignment: .top)
            DashboardFooterContainer(
                store: store,
                togglePet: togglePet,
                showPet: showPet,
                openSettings: openSettings,
                dismiss: dismiss
            )
        }
        .padding(DashboardDesign.outerPadding)
        .frame(
            width: hostModel.width,
            height: DashboardPanelLayout.height(
                for: panelState.selectedSection,
                musicSource: playback.source,
                maximumHeight: hostModel.maximumHeight
            )
        )
        .background { DashboardAtmosphereContainer(store: store) }
        .tint(palette.accent)
        .environment(\.dashboardVisualTreatment, palette.treatment)
        .preferredColorScheme(palette.preferredColorScheme)
        .opacity(hostModel.isPresented ? 1 : 0)
        .onAppear(perform: prepareDashboard)
        .onChange(of: panelState.selectedSection) { _, section in
            layoutDidChange(section, playback.source)
        }
        .onChange(of: playback.source) { _, source in
            layoutDidChange(panelState.selectedSection, source)
        }
        .onExitCommand(perform: dismiss)
        .onMoveCommand(perform: moveSelection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("元圭与 VCC 快速控制中心")
    }

    private func prepareDashboard() {
        updater.setTerminationHandler(appActions.terminateForUpdate)
        store.refreshDesktopIconVisibility()
        store.monitor.refresh()
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let next = panelState.selectedSection.adjacent(direction)
        guard next != panelState.selectedSection else { return }
        withAnimation(
            reduceMotion ? nil : .snappy(duration: DashboardDesign.navigationAnimationDuration)
        ) {
            panelState.selectedSection = next
        }
    }
}
