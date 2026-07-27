import SwiftUI

struct DashboardFocusButton: View {
    let title: String
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(AppLocalizer.string(title), systemImage: "timer")
                .font(.caption)
        }
        .dashboardSystemGlassButton(isProminent: isRunning)
        .controlSize(.small)
        .help(isRunning ? "\(AppLocalizer.string("专注中"))：\(AppLocalizer.string(title))" : AppLocalizer.string("打开番茄钟"))
        .accessibilityLabel(isRunning ? "\(AppLocalizer.string("番茄钟"))，\(AppLocalizer.string("剩余")) \(AppLocalizer.string(title))" : AppLocalizer.string("打开番茄钟"))
    }
}
