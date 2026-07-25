import SwiftUI

struct DashboardOverviewView: View {
    @ObservedObject var store: PetStore

    private var snapshot: SystemSnapshot { store.monitor.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: DashboardDesign.compactSpacing) {
                DashboardWeatherSummaryView(weather: store.weather)
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: DashboardDesign.compactSpacing),
                        GridItem(.flexible(), spacing: DashboardDesign.compactSpacing)
                    ],
                    spacing: DashboardDesign.compactSpacing
                ) {
                    cpuTile
                    memoryTile
                    diskTile
                    networkTile
                }
                DashboardPowerStatusRow(snapshot: snapshot)
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("概览")
    }

    private var cpuTile: some View {
        let value = snapshot.cpu?.total
        let severity: DashboardStatusSeverity = (value ?? 0) >= 0.9 ? .warning : .normal
        return DashboardMetricTile(
            title: "CPU",
            systemImage: "cpu",
            primaryValue: value.map(MetricFormatting.percent) ?? "—",
            detail: snapshot.cpu.map { "用户 \(MetricFormatting.percent($0.user))" } ?? availability(.cpu),
            status: value == nil ? "等待采样" : ((value ?? 0) >= 0.9 ? "负载较高" : "正常"),
            severity: severity,
            history: snapshot.history.cpu,
            fixedMaximum: 1
        )
    }

    private var memoryTile: some View {
        let memory = snapshot.memory
        let severity: DashboardStatusSeverity
        let status: String
        switch memory?.pressure {
        case .warning:
            severity = .warning
            status = "有压力"
        case .critical:
            severity = .critical
            status = "紧张"
        default:
            severity = .normal
            status = memory == nil ? "等待采样" : "正常"
        }
        return DashboardMetricTile(
            title: "内存",
            systemImage: "memorychip",
            primaryValue: memory.map { MetricFormatting.percent($0.fractionUsed) } ?? "—",
            detail: memory.map { "\(MetricFormatting.bytes($0.used)) / \(MetricFormatting.bytes($0.total))" } ?? availability(.memory),
            status: status,
            severity: severity,
            history: snapshot.history.memory,
            fixedMaximum: 1
        )
    }

    private var diskTile: some View {
        let disk = snapshot.disk
        let fraction = disk?.fractionUsed ?? 0
        let severity: DashboardStatusSeverity = fraction >= 0.95 ? .critical : (fraction >= 0.85 ? .warning : .normal)
        return DashboardMetricTile(
            title: "磁盘",
            systemImage: "internaldrive",
            primaryValue: disk.map { MetricFormatting.bytes($0.free) } ?? "—",
            detail: disk.map { "可用 · 共 \(MetricFormatting.bytes($0.total))" } ?? availability(.disk),
            status: disk == nil ? "等待采样" : (fraction >= 0.85 ? "空间偏少" : "可用"),
            severity: severity,
            progress: fraction
        )
    }

    private var networkTile: some View {
        let network = snapshot.network
        return DashboardMetricTile(
            title: "网络",
            systemImage: "arrow.down.circle",
            primaryValue: network.map { "↓ \(MetricFormatting.rate($0.downloadRate))" } ?? "—",
            detail: network.map { "↑ \(MetricFormatting.rate($0.uploadRate))" } ?? availability(.network),
            status: network == nil ? "等待采样" : "实时",
            severity: .informational
        )
    }

    private func availability(_ identifier: MetricIdentifier) -> String {
        snapshot.isAvailable(identifier) ? "等待首次采样" : "暂不可用"
    }
}

struct DashboardPowerStatusRow: View {
    let snapshot: SystemSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(severity.color)
                .accessibilityHidden(true)
            Text(powerText)
                .lineLimit(1)
            Spacer(minLength: 6)
            Label("已运行 \(MetricFormatting.uptime(snapshot.uptime))", systemImage: "clock")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 4)
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
    }

    private var severity: DashboardStatusSeverity {
        guard let battery = snapshot.battery, battery.isPresent, !battery.isCharging else { return .normal }
        guard let fraction = battery.chargeFraction else { return .informational }
        return fraction <= 0.1 ? .critical : (fraction <= 0.2 ? .warning : .normal)
    }

    private var icon: String {
        guard let battery = snapshot.battery, battery.isPresent else { return "powerplug.fill" }
        if battery.isCharging { return "battery.100percent.bolt" }
        return "battery.75percent"
    }

    private var powerText: String {
        guard snapshot.isAvailable(.battery), let battery = snapshot.battery else { return "电源暂不可用" }
        guard battery.isPresent else { return "交流电源" }
        var parts = [battery.chargeFraction.map(MetricFormatting.percent) ?? "电量未知"]
        parts.append(battery.isCharging ? "充电中" : (battery.powerSource == .ac ? "已接电源" : "使用电池"))
        if let minutes = battery.timeRemainingMinutes, minutes > 0 {
            parts.append("约\(minutes / 60)小时\(minutes % 60)分")
        }
        return parts.joined(separator: " · ")
    }
}
