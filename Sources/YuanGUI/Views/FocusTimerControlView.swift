import SwiftUI

struct FocusTimerControlView: View {
    @ObservedObject var timer: FocusTimerStore
    let showPet: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                tomatoDial
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLocalizer.string("陪伴式专注"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(timer.statusTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            if timer.state == .idle || timer.state == .completed {
                HStack(spacing: 6) {
                    ForEach([15, 25, 45, 60], id: \.self) { minutes in
                        Button("\(minutes)") { timer.setDurationMinutes(minutes) }
                            .buttonStyle(.bordered)
                            .tint(timer.durationMinutes == minutes ? .red : .secondary)
                            .controlSize(.mini)
                    }
                    Spacer()
                    Stepper(
                        AppLocalizer.format("focus.minutes", timer.durationMinutes),
                        value: Binding(
                            get: { timer.durationMinutes },
                            set: timer.setDurationMinutes
                        ),
                        in: FocusTimerStore.minimumDurationMinutes...FocusTimerStore.maximumDurationMinutes,
                        step: 5
                    )
                        .controlSize(.mini)
                        .fixedSize()
                }
            } else {
                ProgressView(value: timer.progress)
                    .tint(.red)
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(AppLocalizer.string("专注时自动隐藏日常、天气和非紧急气泡"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    controls
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(
            LinearGradient(
                colors: [.red.opacity(0.13), .orange.opacity(0.07), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var tomatoDial: some View {
        ZStack {
            Circle().stroke(.red.opacity(0.14), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(timer.progress, 0.025))
                .stroke(
                    AngularGradient(colors: [.red, .orange, .red], center: .center),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text(timer.state == .idle ? "🍅" : timer.timeText)
                .font(timer.state == .idle ? .system(size: 25) : .system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 58, height: 58)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            switch timer.state {
            case .idle, .completed:
                Button(AppLocalizer.string("开始")) { timer.start(); showPet() }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .fixedSize(horizontal: true, vertical: false)
            case .running:
                Button(AppLocalizer.string("暂停")) { timer.pause() }
                    .fixedSize(horizontal: true, vertical: false)
                Button(AppLocalizer.string("结束")) { timer.stop() }
                    .fixedSize(horizontal: true, vertical: false)
            case .paused:
                Button(AppLocalizer.string("继续")) { timer.resume() }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .fixedSize(horizontal: true, vertical: false)
                Button(AppLocalizer.string("结束")) { timer.stop() }
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
