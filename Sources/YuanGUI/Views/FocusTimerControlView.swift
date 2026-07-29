import SwiftUI

struct FocusTimerControlView: View {
    @ObservedObject var timer: FocusTimerStore
    let showPet: () -> Void
    @State private var dragStartDuration: Int?

    private let dialSize: CGFloat = 82

    var body: some View {
        VStack(spacing: 10) {
            tomatoDial

            if timer.state == .idle || timer.state == .completed {
                Button(AppLocalizer.string("开始")) {
                    timer.start()
                    showPet()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
            } else {
                ProgressView(value: timer.progress)
                    .tint(.red)
                    .frame(width: 112)

                HStack(spacing: 6) {
                    if timer.state == .paused {
                        Button(AppLocalizer.string("继续")) { timer.resume() }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.mini)
                            .fixedSize(horizontal: true, vertical: false)
                    } else {
                        Button(AppLocalizer.string("暂停")) { timer.pause() }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Button(AppLocalizer.string("结束")) { timer.stop() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(10)
        .frame(width: 140)
        .background(
            LinearGradient(
                colors: [.red.opacity(0.13), .orange.opacity(0.07), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalizer.string("陪伴式专注"))
    }

    private var tomatoDial: some View {
        ZStack {
            Circle()
                .stroke(.red.opacity(0.14), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(timer.progress, 0.025))
                .stroke(
                    AngularGradient(colors: [.red, .orange, .red], center: .center),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if timer.state == .idle || timer.state == .completed {
                Text("🍅")
                    .font(.system(size: 31))
                Text(AppLocalizer.format("focus.minutes.short", timer.durationMinutes))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
                    .offset(y: 28)
            } else {
                Text(timer.timeText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .frame(width: dialSize, height: dialSize)
        .contentShape(Circle())
        .gesture(durationDrag)
        .accessibilityValue(
            timer.state == .idle || timer.state == .completed
                ? AppLocalizer.format("focus.minutes", timer.durationMinutes)
                : timer.timeText
        )
        .accessibilityHint(
            timer.state == .idle || timer.state == .completed
                ? AppLocalizer.string("focus.adjustDurationHint")
                : ""
        )
        .help(
            timer.state == .idle || timer.state == .completed
                ? AppLocalizer.string("focus.adjustDurationHint")
                : AppLocalizer.string("专注中")
        )
    }

    private var durationDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard timer.state == .idle || timer.state == .completed else { return }
                if dragStartDuration == nil {
                    dragStartDuration = timer.durationMinutes
                }

                let start = dragStartDuration ?? timer.durationMinutes
                timer.setDurationMinutes(
                    FocusTimerDurationGesture.adjustedDuration(
                        startDuration: start,
                        translation: value.translation
                    )
                )
            }
            .onEnded { _ in
                dragStartDuration = nil
            }
    }
}

enum FocusTimerDurationGesture {
    static let pixelsPerStep: CGFloat = 12
    static let minutesPerStep = 5

    static func adjustedDuration(startDuration: Int, translation: CGSize) -> Int {
        let movement = abs(translation.width) > abs(translation.height)
            ? translation.width
            : -translation.height
        let steps = Int((movement / pixelsPerStep).rounded())
        return startDuration + steps * minutesPerStep
    }
}
