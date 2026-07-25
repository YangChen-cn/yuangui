import SwiftUI

struct DashboardHeaderView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var focusTimer: FocusTimerStore
    @Binding var showsFocusPopover: Bool
    let showPet: () -> Void

    private var smartState: DashboardSmartStatePresentation {
        .resolve(store.smartState)
    }

    var body: some View {
        HStack(spacing: 11) {
            DashboardPetAvatarView(mode: store.mode)
            VStack(alignment: .leading, spacing: 2) {
                Text(DashboardHeaderPresentation.greeting(at: .now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(DashboardHeaderPresentation.companionTitle(for: store.mode))
                    .font(.headline)
                    .bold()
                    .lineLimit(1)
                Text(Date.now, format: .dateTime.month().day().weekday(.wide))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 7) {
                DashboardFocusButton(
                    title: focusButtonTitle,
                    isRunning: focusTimer.state == .running,
                    action: toggleFocusPopover
                )
                .popover(isPresented: $showsFocusPopover, arrowEdge: .top) {
                    FocusTimerControlView(timer: focusTimer, showPet: showPet)
                }
                DashboardStatusLabel(presentation: smartState)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: DashboardDesign.avatarSize)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("面板顶部")
    }

    private var focusButtonTitle: String {
        focusTimer.state == .running ? focusTimer.timeText : "番茄钟"
    }

    private func toggleFocusPopover() {
        showsFocusPopover.toggle()
    }
}
