import SwiftUI

struct MenuBarDashboardView: View {
    static let preferredWidth = DashboardDesign.preferredWidth

    @ObservedObject var store: PetStore
    @ObservedObject var focusTimer: FocusTimerStore
    @ObservedMusicFeature var music: MusicFeature
    @ObservedObject var externalAudioInterruption: ExternalAudioInterruptionController
    @ObservedObject var quickTools: QuickToolsController
    let dashboardWidth: CGFloat
    let dashboardHeight: CGFloat
    let togglePet: () -> Void
    let showPet: () -> Void
    let openSettings: () -> Void
    let dismiss: () -> Void

    @Environment(\.appActions) private var appActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var updater = AppUpdateStore()
    @State private var selectedSection = DashboardSection.overview
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
            DashboardSectionPicker(selection: $selectedSection)
            pageContent
                .frame(maxWidth: .infinity, alignment: .top)
            DashboardFooterView(
                store: store,
                togglePet: togglePet,
                showPet: showPet
            )
        }
        .padding(DashboardDesign.outerPadding)
        .frame(width: dashboardWidth, height: dashboardHeight)
        .background {
            DashboardAtmosphereBackground(palette: palette)
        }
        .tint(palette.accent)
        .preferredColorScheme(palette.preferredColorScheme)
        .onAppear(perform: prepareDashboard)
        .onExitCommand(perform: dismiss)
        .onMoveCommand(perform: moveSelection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("元圭与 VCC 快速控制中心")
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedSection {
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
        let next = selectedSection.adjacent(direction)
        guard next != selectedSection else { return }
        if reduceMotion {
            selectedSection = next
        } else {
            withAnimation(.easeInOut(duration: DashboardDesign.animationDuration)) {
                selectedSection = next
            }
        }
    }
}
