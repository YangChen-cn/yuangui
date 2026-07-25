import SwiftUI

struct DashboardFocusButton: View {
    let title: String
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "timer")
                .font(.caption)
        }
        .dashboardSystemGlassButton(isProminent: isRunning)
        .controlSize(.small)
        .help(isRunning ? "专注中：\(title)" : "打开番茄钟")
        .accessibilityLabel(isRunning ? "番茄钟，剩余 \(title)" : "打开番茄钟")
    }
}
