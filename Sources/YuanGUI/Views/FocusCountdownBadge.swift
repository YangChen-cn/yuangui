import SwiftUI

struct FocusCountdownBadge: View {
    @ObservedObject var timer: FocusTimerStore
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: timer.state == .paused
                            ? [.red.opacity(0.76), .orange.opacity(0.78)]
                            : [.red, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(timer.timeText)
                .font(.system(size: max(8, size * 0.22), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .padding(.horizontal, 4)
            Circle()
                .trim(from: 0, to: max(timer.progress, 0.03))
                .stroke(.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 0.9))
        .shadow(color: .red.opacity(0.24), radius: 8, y: 3)
        .contentShape(Circle())
    }
}

struct FocusIdleBadge: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.92), .red.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("🍅")
                .font(.system(size: size * 0.52))
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 0.9))
        .shadow(color: .red.opacity(0.24), radius: 8, y: 3)
        .contentShape(Circle())
    }
}
