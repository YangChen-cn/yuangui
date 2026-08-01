import SwiftUI

struct MenuBarDashboardView: View {
    static let preferredWidth = DashboardDesign.preferredWidth

    let width: CGFloat
    let maximumHeight: CGFloat
    let store: PetStore
    let focusTimer: FocusTimerStore
    let music: MusicFeature
    let externalAudioInterruption: ExternalAudioInterruptionController
    let quickTools: QuickToolsController
    let panelState: DashboardPanelState
    let updater: AppUpdateStore
    let togglePet: () -> Void
    let showPet: () -> Void
    let openSettings: () -> Void
    let dismiss: () -> Void
    let layoutDidChange: (DashboardSection, MusicSource) -> Void

    var body: some View {
        DashboardAppearanceContainer(store: store) {
            DashboardLayoutContainer(
                width: width,
                maximumHeight: maximumHeight,
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
        }
    }
}

private struct DashboardLayoutContainer: View {
    let width: CGFloat
    let maximumHeight: CGFloat
    let store: PetStore
    let focusTimer: FocusTimerStore
    let music: MusicFeature
    let externalAudioInterruption: ExternalAudioInterruptionController
    let quickTools: QuickToolsController
    @ObservedObject var panelState: DashboardPanelState
    let updater: AppUpdateStore
    let togglePet: () -> Void
    let showPet: () -> Void
    let openSettings: () -> Void
    let dismiss: () -> Void
    let layoutDidChange: (DashboardSection, MusicSource) -> Void

    @ObservedObject private var playback: MusicPlaybackStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        width: CGFloat,
        maximumHeight: CGFloat,
        store: PetStore,
        focusTimer: FocusTimerStore,
        music: MusicFeature,
        externalAudioInterruption: ExternalAudioInterruptionController,
        quickTools: QuickToolsController,
        panelState: DashboardPanelState,
        updater: AppUpdateStore,
        togglePet: @escaping () -> Void,
        showPet: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        dismiss: @escaping () -> Void,
        layoutDidChange: @escaping (DashboardSection, MusicSource) -> Void
    ) {
        self.width = width
        self.maximumHeight = maximumHeight
        self.store = store
        self.focusTimer = focusTimer
        self.music = music
        self.externalAudioInterruption = externalAudioInterruption
        self.quickTools = quickTools
        self.panelState = panelState
        self.updater = updater
        self.togglePet = togglePet
        self.showPet = showPet
        self.openSettings = openSettings
        self.dismiss = dismiss
        self.layoutDidChange = layoutDidChange
        _playback = ObservedObject(wrappedValue: music.playback)
    }

    var body: some View {
        let height = min(
            DashboardPanelLayout.height(
                for: panelState.selectedSection,
                musicSource: playback.source,
                maximumHeight: maximumHeight
            ),
            maximumHeight
        )

        DashboardContentRoot(
            width: width,
            store: store,
            focusTimer: focusTimer,
            music: music,
            externalAudioInterruption: externalAudioInterruption,
            quickTools: quickTools,
            selection: panelState.selectedSection,
            selectionBinding: $panelState.selectedSection,
            updater: updater,
            togglePet: togglePet,
            showPet: showPet,
            openSettings: openSettings,
            dismiss: dismiss
        )
        .frame(
            width: width,
            height: height,
            alignment: .top
        )
        .background { DashboardAtmosphereContainer(store: store) }
        .onChange(of: panelState.selectedSection) { _, section in
            layoutDidChange(section, playback.source)
        }
        .onChange(of: playback.source) { _, source in
            layoutDidChange(panelState.selectedSection, source)
        }
        .onMoveCommand { direction in
            let next = panelState.selectedSection.adjacent(direction)
            guard next != panelState.selectedSection else { return }
            withAnimation(
                reduceMotion ? nil : .snappy(duration: DashboardDesign.navigationAnimationDuration)
            ) {
                panelState.selectedSection = next
            }
        }
    }
}

private struct DashboardContentRoot: View {
    let width: CGFloat
    let store: PetStore
    let focusTimer: FocusTimerStore
    let music: MusicFeature
    let externalAudioInterruption: ExternalAudioInterruptionController
    let quickTools: QuickToolsController
    let selection: DashboardSection
    let selectionBinding: Binding<DashboardSection>
    let updater: AppUpdateStore
    let togglePet: () -> Void
    let showPet: () -> Void
    let openSettings: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: DashboardDesign.sectionSpacing) {
            DashboardHeaderContainer(
                store: store,
                focusTimer: focusTimer,
                showPet: showPet
            )
            DashboardSectionPicker(selection: selectionBinding)
            DashboardPageContainer(
                selection: selection,
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
        .frame(width: width, alignment: .top)
        .onExitCommand(perform: dismiss)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("元圭与 VCC 快速控制中心")
    }
}
