import SwiftUI

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
            Label("\(AppLocalizer.string("已运行")) \(MetricFormatting.uptime(snapshot.uptime))", systemImage: "clock")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.caption)
        .frame(minHeight: DashboardDesign.rowHeight)
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
        guard snapshot.isAvailable(.battery), let battery = snapshot.battery else { return AppLocalizer.string("电源暂不可用") }
        guard battery.isPresent else { return AppLocalizer.string("交流电源") }
        var parts = [battery.chargeFraction.map(MetricFormatting.percent) ?? AppLocalizer.string("电量未知")]
        parts.append(battery.isCharging ? AppLocalizer.string("充电中") : (battery.powerSource == .ac ? AppLocalizer.string("已接电源") : AppLocalizer.string("使用电池")))
        if let minutes = battery.timeRemainingMinutes, minutes > 0 {
            parts.append("\(AppLocalizer.string("约"))\(minutes / 60)\(AppLocalizer.string("小时"))\(minutes % 60)\(AppLocalizer.string("分"))")
        }
        return parts.joined(separator: " · ")
    }
}
