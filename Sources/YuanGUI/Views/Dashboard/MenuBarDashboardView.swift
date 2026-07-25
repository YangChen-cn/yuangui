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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
            Divider()
            DashboardFooterView(
                store: store,
                togglePet: togglePet,
                showPet: showPet,
                openSettings: openSettings
            )
        }
        .padding(DashboardDesign.outerPadding)
        .frame(width: dashboardWidth, height: dashboardHeight)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .background(DashboardDesign.atmosphere(for: store.dashboardStyle), in: .rect(cornerRadius: 20))
        .tint(DashboardDesign.accent(for: store.dashboardStyle))
        .preferredColorScheme(store.dashboardStyle == .midnight ? .dark : nil)
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
            ScrollView {
                VStack(spacing: DashboardDesign.compactSpacing) {
                    WeatherStatusCard(weather: store.weather)
                    SystemStatusCard(monitor: store.monitor)
                }
            }
            .scrollIndicators(.hidden)
        case .music:
            MusicStatusCard(music: music, externalAudioInterruption: externalAudioInterruption)
        case .tools:
            DashboardToolsLegacyBridge(
                store: store,
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
