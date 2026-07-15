import SwiftUI

struct FocusTimerControlView: View {
    @ObservedObject var timer: FocusTimerStore
    let showPet: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                tomatoDial
                VStack(alignment: .leading, spacing: 3) {
                    Text("陪伴式专注")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(timer.statusTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if timer.state == .idle || timer.state == .completed {
                HStack(spacing: 6) {
                    ForEach([15, 25, 45, 60], id: \.self) { minutes in
                        Button("\(minutes)") { timer.durationMinutes = minutes }
                            .buttonStyle(.bordered)
                            .tint(timer.durationMinutes == minutes ? .red : .secondary)
                            .controlSize(.small)
                    }
                    Spacer()
                    Stepper("\(timer.durationMinutes) 分钟", value: $timer.durationMinutes, in: 1...180, step: 5)
                        .fixedSize()
                }
            } else {
                ProgressView(value: timer.progress)
                    .tint(.red)
            }

            HStack {
                Text("专注时自动隐藏日常、天气和非紧急气泡")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                controls
            }
        }
        .padding(16)
        .frame(width: 340)
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
        switch timer.state {
        case .idle, .completed:
            Button("开始") { timer.start(); showPet() }
                .buttonStyle(.borderedProminent).tint(.red)
        case .running:
            Button("暂停") { timer.pause() }
            Button("结束") { timer.stop() }
        case .paused:
            Button("继续") { timer.resume() }
                .buttonStyle(.borderedProminent).tint(.red)
            Button("结束") { timer.stop() }
        }
    }
}
