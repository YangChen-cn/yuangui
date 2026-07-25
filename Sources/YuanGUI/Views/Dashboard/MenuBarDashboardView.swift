import SwiftUI

struct MenuBarDashboardView: View {
    static let preferredWidth = DashboardDesign.preferredWidth

    @ObservedObject var store: PetStore
    @ObservedObject var focusTimer: FocusTimerStore
    @ObservedMusicFeature var music: MusicFeature
    @ObservedObject var externalAudioInterruption: ExternalAudioInterruptionController
    @ObservedObject var quickTools: QuickToolsController
    @ObservedObject var panelState: DashboardPanelState
    let dashboardWidth: CGFloat
    let dashboardHeight: CGFloat
    let togglePet: () -> Void
    let showPet: () -> Void
    let openSettings: () -> Void
    let dismiss: () -> Void
    let sectionDidChange: (DashboardSection) -> Void

    @Environment(\.appActions) private var appActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var updater = AppUpdateStore()
    @State private var showsFocusPopover = false

    private var palette: DashboardPalette {
        DashboardDesign.palette(for: store.dashboardStyle)
    }

    var body: some View {
        VStack(spacing: DashboardDesign.sectionSpacing) {
            DashboardHeaderView(
                store: store,
                focusTimer: focusTimer,
                showsFocusPopover: $showsFocusPopover,
                showPet: showPet
            )
            DashboardSectionPicker(selection: $panelState.selectedSection)
            pageContent
                .frame(maxWidth: .infinity, alignment: .top)
            DashboardFooterView(
                store: store,
                togglePet: togglePet,
                showPet: showPet,
                openSettings: openSettings,
                dismiss: dismiss
            )
        }
        .padding(DashboardDesign.outerPadding)
        .frame(
            width: dashboardWidth,
            height: DashboardPanelLayout.height(
                for: panelState.selectedSection,
                maximumHeight: dashboardHeight
            )
        )
        .background {
            DashboardAtmosphereBackground(
                palette: palette,
                mode: store.mode,
                smartState: store.smartState
            )
        }
        .tint(palette.accent)
        .environment(\.dashboardVisualTreatment, palette.treatment)
        .preferredColorScheme(palette.preferredColorScheme)
        .onAppear(perform: prepareDashboard)
        .onChange(of: panelState.selectedSection) { _, section in
            sectionDidChange(section)
        }
        .onExitCommand(perform: dismiss)
        .onMoveCommand(perform: moveSelection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("元圭与 VCC 快速控制中心")
    }

    @ViewBuilder
    private var pageContent: some View {
        switch panelState.selectedSection {
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
