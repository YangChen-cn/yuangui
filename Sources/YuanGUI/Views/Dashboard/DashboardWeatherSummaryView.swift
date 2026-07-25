import AppKit
import SwiftUI

struct DashboardWeatherSummaryView: View {
    @ObservedObject var weather: WeatherService

    var body: some View {
        DashboardWeatherSummaryContent(
            presentation: .resolve(
                snapshot: weather.snapshot,
                status: weather.status,
                locationName: weather.locationName
            ),
            onRefresh: weather.refresh,
            onOpenLocationSettings: openLocationSettings
        )
    }

    private func openLocationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

struct DashboardWeatherSummaryContent: View {
    let presentation: DashboardWeatherPresentation
    let onRefresh: () -> Void
    let onOpenLocationSettings: () -> Void

    var body: some View {
        DashboardSectionSurface(prominence: .hero) {
            HStack(spacing: 11) {
                Image(systemName: presentation.icon)
                    .font(.title2)
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(presentation.primaryText)
                            .font(.title3)
                            .bold()
                        Text(presentation.conditionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(presentation.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(presentation.metadataText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if presentation.showsLocationSettings {
                    Button("打开设置", action: onOpenLocationSettings)
                        .controlSize(.small)
                }
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                    .buttonStyle(.borderless)
                    .disabled(presentation.isRefreshing)
                    .help(presentation.isRefreshing ? "正在刷新天气" : "刷新天气")
                    .accessibilityLabel("刷新天气")
            }
            .accessibilityElement(children: .contain)
        }
    }

}
