import SwiftUI

struct FocusTimerControlView: View {
    @ObservedObject var timer: FocusTimerStore
    let showPet: () -> Void

    private let dialSize: CGFloat = 76

    var body: some View {
        VStack(spacing: 6) {
            header
            focusDial
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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.easeOut(duration: 0.22), value: timer.state)
        .animation(.easeOut(duration: 0.2), value: timer.progress)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalizer.string("陪伴式专注"))
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "timer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            Text(AppLocalizer.string("专注"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var focusDial: some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.10), lineWidth: 5)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    AngularGradient(colors: [.red, .orange, .red], center: .center),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            dialContent
        }
        .frame(width: dialSize, height: dialSize)
        .accessibilityValue(accessibilityDialValue)
    }

    @ViewBuilder
    private var dialContent: some View {
        switch timer.state {
        case .idle:
            Text(AppLocalizer.format("focus.minutes.short", timer.durationMinutes))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
        case .running:
            Text(timer.timeText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        case .paused:
            VStack(spacing: 1) {
                Text(AppLocalizer.string("已暂停"))
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(timer.timeText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: timer.state)
        }
    }

    @ViewBuilder
    private var durationAdjuster: some View {
        if timer.state == .idle || timer.state == .completed {
            HStack(spacing: 5) {
                durationButton("minus", label: "减少专注时长") {
                    timer.setDurationMinutes(timer.durationMinutes - 5)
                }

                Text(AppLocalizer.format("focus.minutes.short", timer.durationMinutes))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 52)
                    .contentTransition(.numericText())

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
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.mini)
            .fixedSize(horizontal: true, vertical: false)
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
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .accessibilityLabel(AppLocalizer.string(label))
    }

    private func iconControl(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 25, height: 21)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .accessibilityLabel(AppLocalizer.string(label))
        .help(AppLocalizer.string(label))
    }

    private var ringProgress: Double {
        switch timer.state {
        case .idle: return 0.025
        case .running, .paused, .completed: return max(timer.progress, 0.025)
        }
    }

    private var accessibilityDialValue: String {
        switch timer.state {
        case .idle: return AppLocalizer.format("focus.minutes", timer.durationMinutes)
        case .running, .paused: return timer.timeText
        case .completed: return AppLocalizer.string("完成一轮")
        }
    }
}
