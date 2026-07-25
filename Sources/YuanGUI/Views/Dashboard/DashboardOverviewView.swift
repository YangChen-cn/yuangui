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
                }
                DashboardSecondaryMetrics(snapshot: snapshot)
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
            status: value == nil ? "等待采样" : ((value ?? 0) >= 0.9 ? "负载较高" : ""),
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
            status: severity == .normal ? "" : status,
            severity: severity,
            history: snapshot.history.memory,
            fixedMaximum: 1
        )
    }

    private func availability(_ identifier: MetricIdentifier) -> String {
        snapshot.isAvailable(identifier) ? "等待首次采样" : "暂不可用"
    }
}
