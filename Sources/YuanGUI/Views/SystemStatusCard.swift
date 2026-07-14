import SwiftUI

struct SystemStatusCard: View {
    @ObservedObject var monitor: SystemMonitor

    private var snapshot: SystemSnapshot { monitor.snapshot }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Mac 状态", systemImage: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text("已运行 \(MetricFormatting.uptime(snapshot.uptime))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            StatusMetricRow(
                icon: "cpu",
                title: "CPU",
                detail: cpuDetail,
                value: snapshot.cpu?.total,
                history: snapshot.history.cpu,
                tint: .pink,
                available: snapshot.isAvailable(.cpu)
            )
            StatusMetricRow(
                icon: "memorychip",
                title: "内存",
                detail: memoryDetail,
                value: snapshot.memory?.fractionUsed,
                history: snapshot.history.memory,
                tint: memoryTint,
                available: snapshot.isAvailable(.memory)
            )
            StatusMetricRow(
                icon: "internaldrive",
                title: "磁盘",
                detail: diskDetail,
                value: snapshot.disk?.fractionUsed,
                history: [],
                tint: .blue,
                available: snapshot.isAvailable(.disk)
            )
            NetworkStatusRow(metrics: snapshot.network, history: snapshot.history, available: snapshot.isAvailable(.network))
            BatteryStatusRow(metrics: snapshot.battery, available: snapshot.isAvailable(.battery))
        }
        .padding(15)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.17), radius: 20, y: 9)
    }

    private var cpuDetail: String {
        guard let cpu = snapshot.cpu else { return "等待采样" }
        return "\(MetricFormatting.percent(cpu.total)) · 用户 \(MetricFormatting.percent(cpu.user))"
    }

    private var memoryDetail: String {
        guard let memory = snapshot.memory else { return "等待采样" }
        let pressure: String
        switch memory.pressure {
        case .normal: pressure = "正常"
        case .warning: pressure = "有压力"
        case .critical: pressure = "紧张"
        }
        return "\(MetricFormatting.bytes(memory.used)) / \(MetricFormatting.bytes(memory.total)) · \(pressure)"
    }

    private var memoryTint: Color {
        switch snapshot.memory?.pressure {
        case .warning: return .orange
        case .critical: return .red
        default: return .purple
        }
    }

    private var diskDetail: String {
        guard let disk = snapshot.disk else { return "等待采样" }
        return "剩余 \(MetricFormatting.bytes(disk.free))"
    }
}

private struct StatusMetricRow: View {
    let icon: String
    let title: String
    let detail: String
    let value: Double?
    let history: [Double]
    let tint: Color
    let available: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .frame(width: 17)
                .foregroundStyle(available ? tint : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text(available ? detail : "暂不可用")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    ProgressView(value: min(max(value ?? 0, 0), 1))
                        .tint(available ? tint : .gray)
                    MiniSparkline(values: history, fixedMaximum: 1, color: tint)
                        .frame(width: 68, height: 13)
                }
            }
        }
    }
}

private struct NetworkStatusRow: View {
    let metrics: NetworkMetrics?
    let history: MetricHistory
    let available: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.up.arrow.down.circle")
                .frame(width: 17)
                .foregroundStyle(available ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("网络")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text(detail)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Label(MetricFormatting.rate(metrics?.downloadRate ?? 0), systemImage: "arrow.down")
                        .foregroundStyle(.green)
                    Label(MetricFormatting.rate(metrics?.uploadRate ?? 0), systemImage: "arrow.up")
                        .foregroundStyle(.orange)
                    Spacer(minLength: 0)
                    MiniSparkline(values: history.download, color: .green)
                        .frame(width: 68, height: 13)
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
            }
        }
    }

    private var detail: String { available ? "实时速度" : "暂不可用" }
}

private struct BatteryStatusRow: View {
    let metrics: BatteryMetrics?
    let available: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .frame(width: 17)
                .foregroundStyle(available ? Color.mint : Color.secondary)
            Text("电源")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer()
            if let fraction = metrics?.chargeFraction {
                ProgressView(value: fraction)
                    .tint(fraction < 0.2 ? .red : .mint)
                    .frame(width: 58)
            }
        }
    }

    private var icon: String {
        guard let metrics, metrics.isPresent else { return "powerplug" }
        return metrics.isCharging ? "battery.100percent.bolt" : "battery.75percent"
    }

    private var detail: String {
        guard available, let metrics else { return "暂不可用" }
        guard metrics.isPresent else { return "交流电源" }
        var parts: [String] = []
        if let fraction = metrics.chargeFraction { parts.append(MetricFormatting.percent(fraction)) }
        parts.append(metrics.isCharging ? "充电中" : metrics.powerSource == .ac ? "已接电源" : "使用电池")
        if let minutes = metrics.timeRemainingMinutes, minutes > 0 {
            parts.append("约\(minutes / 60)小时\(minutes % 60)分")
        }
        return parts.joined(separator: " · ")
    }
}

private struct MiniSparkline: View {
    let values: [Double]
    var fixedMaximum: Double? = nil
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard values.count > 1 else { return }
                let maximum = max(fixedMaximum ?? values.max() ?? 1, 0.000_001)
                let step = geometry.size.width / CGFloat(values.count - 1)
                for (index, value) in values.enumerated() {
                    let x = CGFloat(index) * step
                    let y = geometry.size.height * (1 - CGFloat(min(max(value / maximum, 0), 1)))
                    index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
