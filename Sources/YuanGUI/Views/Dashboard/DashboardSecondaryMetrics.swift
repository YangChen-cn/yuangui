import SwiftUI

struct DashboardSecondaryMetrics: View {
    let snapshot: SystemSnapshot

    var body: some View {
        VStack(spacing: 0) {
            DashboardCompactMetricRow(
                title: "磁盘",
                systemImage: "internaldrive",
                primaryValue: diskPrimary,
                detail: diskDetail,
                status: diskStatus,
                severity: diskSeverity
            )
            Divider()
                .padding(.leading, 27)
            DashboardCompactMetricRow(
                title: "网络",
                systemImage: "arrow.up.arrow.down",
                primaryValue: networkDownload,
                detail: networkUpload,
                status: "",
                severity: .informational
            )
            Divider()
                .padding(.leading, 27)
            DashboardPowerStatusRow(snapshot: snapshot)
        }
        .padding(.horizontal, 9)
        .background(Color.primary.opacity(0.02), in: .rect(cornerRadius: DashboardDesign.sectionRadius))
    }

    private var diskSeverity: DashboardStatusSeverity {
        let fraction = snapshot.disk?.fractionUsed ?? 0
        return fraction >= 0.95 ? .critical : (fraction >= 0.85 ? .warning : .normal)
    }

    private var diskPrimary: String {
        snapshot.disk.map { "\(MetricFormatting.bytes($0.free)) 可用" }
            ?? availability(.disk)
    }

    private var diskDetail: String {
        snapshot.disk.map { "共 \(MetricFormatting.bytes($0.total))" } ?? ""
    }

    private var diskStatus: String {
        guard snapshot.disk != nil else { return "" }
        return diskSeverity == .normal ? "" : "空间偏少"
    }

    private var networkDownload: String {
        snapshot.network.map { "↓ \(MetricFormatting.rate($0.downloadRate))" }
            ?? availability(.network)
    }

    private var networkUpload: String {
        snapshot.network.map { "↑ \(MetricFormatting.rate($0.uploadRate))" } ?? ""
    }

    private func availability(_ identifier: MetricIdentifier) -> String {
        snapshot.isAvailable(identifier) ? "等待首次采样" : "暂不可用"
    }
}
