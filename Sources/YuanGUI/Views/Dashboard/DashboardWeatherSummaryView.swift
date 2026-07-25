import AppKit
import SwiftUI

struct DashboardWeatherSummaryView: View {
    @ObservedObject var weather: WeatherService

    var body: some View {
        DashboardSectionSurface {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.title2)
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(primaryText)
                            .font(.title3)
                            .bold()
                        Text(conditionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(metadataText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if weather.status == .locationDenied {
                    Button("打开设置", action: openLocationSettings)
                        .controlSize(.small)
                }
                Button("刷新天气", systemImage: "arrow.clockwise", action: weather.refresh)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(isRefreshing)
                    .help(isRefreshing ? "正在刷新天气" : "刷新天气")
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var icon: String {
        if let snapshot = weather.snapshot { return snapshot.condition.symbol }
        return switch weather.status {
        case .locationDenied: "location.slash.fill"
        case .requestingLocation, .loading: "location.fill"
        default: "cloud.sun.fill"
        }
    }

    private var primaryText: String {
        weather.snapshot.map { "\(Int($0.temperature.rounded()))°" } ?? "天气"
    }

    private var conditionText: String {
        if let snapshot = weather.snapshot {
            return "\(snapshot.condition.title) · 体感 \(Int(snapshot.apparentTemperature.rounded()))°"
        }
        return switch weather.status {
        case .idle, .available: "当前位置"
        case .requestingLocation: "正在获取位置"
        case .loading: "正在查询"
        case .locationDenied: "定位未授权"
        case .unavailable: "暂不可用"
        }
    }

    private var detailText: String {
        if let snapshot = weather.snapshot {
            return "湿度 \(snapshot.relativeHumidity)% · 风速 \(Int(snapshot.windSpeed.rounded())) km/h"
        }
        return switch weather.status {
        case .locationDenied: "允许定位后可显示本地天气"
        case .unavailable(let message): message
        case .requestingLocation: "请在系统提示中选择是否允许"
        case .loading: "正在连接天气服务"
        case .idle, .available: "点击刷新获取本地天气"
        }
    }

    private var metadataText: String {
        guard let snapshot = weather.snapshot else { return "无需天气 API Key" }
        return "\(weather.locationName ?? "当前位置") · \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened)) 更新"
    }

    private var isRefreshing: Bool {
        weather.status == .loading || weather.status == .requestingLocation
    }

    private func openLocationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
