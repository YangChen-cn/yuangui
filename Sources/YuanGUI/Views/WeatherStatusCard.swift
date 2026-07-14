import AppKit
import SwiftUI

struct WeatherStatusCard: View {
    @ObservedObject var weather: WeatherService

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 27, weight: .semibold))
                .symbolRenderingMode(.multicolor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    if let snapshot = weather.snapshot {
                        Text("\(Int(snapshot.temperature.rounded()))°")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                }
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Button {
                weather.refresh()
            } label: {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(isRefreshing)
            .help("刷新天气")
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.13), .cyan.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.4), lineWidth: 0.8))
    }

    private var icon: String {
        if let snapshot = weather.snapshot { return snapshot.condition.symbol }
        switch weather.status {
        case .locationDenied: return "location.slash.fill"
        case .loading, .requestingLocation: return "location.fill"
        default: return "cloud.sun.fill"
        }
    }

    private var title: String {
        if let snapshot = weather.snapshot {
            return "\(weather.locationName ?? "当前位置") · \(snapshot.condition.title)"
        }
        switch weather.status {
        case .idle: return "当前位置天气"
        case .requestingLocation: return "正在获取位置"
        case .loading: return "正在查询天气"
        case .locationDenied: return "未获得定位权限"
        case .unavailable: return "天气暂不可用"
        case .available: return "当前位置天气"
        }
    }

    private var detail: String {
        if let snapshot = weather.snapshot {
            if isRefreshing {
                return "正在刷新天气 · 上次 \(updatedTime(snapshot.updatedAt))"
            }
            return "体感 \(Int(snapshot.apparentTemperature.rounded()))° · 湿度 \(snapshot.relativeHumidity)% · 风速 \(Int(snapshot.windSpeed.rounded())) km/h · \(updatedTime(snapshot.updatedAt)) 更新"
        }
        switch weather.status {
        case .idle: return "打开监控后可获取，无需 API Key"
        case .requestingLocation: return "请在系统提示中选择是否允许"
        case .loading: return "正在连接 Open‑Meteo"
        case .locationDenied: return "请在“系统设置 → 隐私与安全性 → 定位服务”中允许"
        case .unavailable(let message): return message
        case .available: return "等待天气数据"
        }
    }

    private var isRefreshing: Bool {
        weather.status == .loading || weather.status == .requestingLocation
    }

    private func updatedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
