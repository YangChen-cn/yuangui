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
                focusButton
                DashboardStatusLabel(presentation: smartState)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: DashboardDesign.avatarSize)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("面板顶部")
    }

    private var focusButton: some View {
        Button {
            showsFocusPopover.toggle()
        } label: {
            Label(focusButtonTitle, systemImage: "timer")
                .font(.caption)
                .foregroundStyle(focusTimer.state == .running ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 8)
                .frame(minHeight: 25)
                .background(
                    focusTimer.state == .running
                        ? Color.accentColor.opacity(0.12)
                        : Color.primary.opacity(0.035),
                    in: .capsule
                )
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(focusTimer.state == .running ? "专注中：\(focusTimer.timeText)" : "打开番茄钟")
        .popover(isPresented: $showsFocusPopover, arrowEdge: .top) {
            FocusTimerControlView(timer: focusTimer, showPet: showPet)
        }
    }

    private var focusButtonTitle: String {
        focusTimer.state == .running ? focusTimer.timeText : "番茄钟"
    }
}
