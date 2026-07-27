import SwiftUI

struct DashboardOverviewView: View {
    @ObservedObject var store: PetStore
    @ObservedObject private var monitor: SystemMonitor

    private var snapshot: SystemSnapshot { monitor.snapshot }

    init(store: PetStore) {
        self.store = store
        monitor = store.monitor
    }

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
            detail: snapshot.cpu.map { "\(AppLocalizer.string("用户")) \(MetricFormatting.percent($0.user))" } ?? availability(.cpu),
            status: value == nil ? AppLocalizer.string("等待采样") : ((value ?? 0) >= 0.9 ? AppLocalizer.string("负载较高") : ""),
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
            status = AppLocalizer.string("有压力")
        case .critical:
            severity = .critical
            status = AppLocalizer.string("紧张")
        default:
            severity = .normal
            status = memory == nil ? AppLocalizer.string("等待采样") : AppLocalizer.string("正常")
        }
        return DashboardMetricTile(
            title: AppLocalizer.string("内存"),
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
        AppLocalizer.string(snapshot.isAvailable(identifier) ? "等待首次采样" : "暂不可用")
    }
}
