import SwiftUI

struct FocusTimerControlView: View {
    @ObservedObject var timer: FocusTimerStore
    let showPet: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            header
            timeDisplay
            durationAdjuster
            stateControls
        }
        .padding(7)
        .frame(width: 148)
        .background(
            LinearGradient(
                colors: [.red.opacity(0.12), .orange.opacity(0.07), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.20),
            value: timer.state
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalizer.string("陪伴式专注"))
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)
            Text(AppLocalizer.string("专注"))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var timeDisplay: some View {
        switch timer.state {
        case .idle:
            primaryTimeText(AppLocalizer.format("focus.minutes.short", timer.durationMinutes))
        case .running:
            primaryTimeText(timer.timeText)
        case .paused:
            VStack(spacing: 0) {
                Text(AppLocalizer.string("已暂停"))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                primaryTimeText(timer.timeText, size: 22)
            }
        case .completed:
            VStack(spacing: 0) {
                completedLabel
                primaryTimeText(
                    AppLocalizer.format("focus.minutes.short", timer.durationMinutes),
                    size: 22
                )
            }
        }
    }

    private func primaryTimeText(_ text: String, size: CGFloat = 25) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText())
    }

    @ViewBuilder
    private var completedLabel: some View {
        let label = Label(AppLocalizer.string("完成一轮"), systemImage: "checkmark.circle.fill")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.green)
        if reduceMotion {
            label
        } else {
            label.symbolEffect(.bounce, value: timer.state)
        }
    }

    @ViewBuilder
    private var durationAdjuster: some View {
        if timer.state == .idle || timer.state == .completed {
            HStack(spacing: 22) {
                durationButton("minus", label: "减少专注时长") {
                    timer.setDurationMinutes(timer.durationMinutes - 5)
                }

                durationButton("plus", label: "增加专注时长") {
                    timer.setDurationMinutes(timer.durationMinutes + 5)
                }
            }
        }
    }

    @ViewBuilder
    private var stateControls: some View {
        switch timer.state {
        case .idle, .completed:
            Button {
                timer.start()
                showPet()
            } label: {
                Label(AppLocalizer.string("开始"), systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FocusPrimaryButtonStyle())
            .accessibilityLabel(AppLocalizer.string("开始"))
        case .running:
            HStack(spacing: 6) {
                iconControl("pause.fill", label: "暂停") { timer.pause() }
                iconControl("stop.fill", label: "结束") { timer.stop() }
            }
        case .paused:
            HStack(spacing: 6) {
                iconControl("play.fill", label: "继续") { timer.resume() }
                iconControl("stop.fill", label: "结束") { timer.stop() }
            }
        }
    }

    private func durationButton(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 22, height: 20)
        }
        .buttonStyle(FocusSecondaryButtonStyle())
        .accessibilityLabel(AppLocalizer.string(label))
        .help(AppLocalizer.string(label))
    }

    private func iconControl(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 28, height: 22)
        }
        .buttonStyle(FocusSecondaryButtonStyle())
        .accessibilityLabel(AppLocalizer.string(label))
        .help(AppLocalizer.string(label))
    }
}

private struct FocusPrimaryButtonStyle: ButtonStyle {
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(
                LinearGradient(
                    colors: [.red, .orange],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .shadow(
                color: .red.opacity(isHovering ? 0.30 : 0.18),
                radius: isHovering ? 8 : 5,
                y: 2
            )
            .scaleEffect(
                reduceMotion
                    ? 1
                    : (configuration.isPressed ? 0.95 : (isHovering ? 1.02 : 1))
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
            .onHover { isHovering = $0 }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: isHovering
            )
    }
}

private struct FocusSecondaryButtonStyle: ButtonStyle {
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary.opacity(0.78))
            .background(
                Color.primary.opacity(isHovering ? 0.13 : 0.07),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(isHovering ? 0.55 : 0.30), lineWidth: 0.7)
            }
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.94 : 1))
            .opacity(configuration.isPressed ? 0.86 : 1)
            .onHover { isHovering = $0 }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: isHovering
            )
    }
}
