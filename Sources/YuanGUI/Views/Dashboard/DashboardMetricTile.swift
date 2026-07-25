import SwiftUI

struct DashboardMetricTile: View {
    let title: String
    let systemImage: String
    let primaryValue: String
    let detail: String
    let status: String
    let severity: DashboardStatusSeverity
    var history: [Double] = []
    var fixedMaximum: Double?
    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .foregroundStyle(severity.color)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption)
                    .bold()
                Spacer(minLength: 4)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(severity.color)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(primaryValue)
                    .font(.title3)
                    .bold()
                    .monospacedDigit()
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let progress {
                    Gauge(value: min(max(progress, 0), 1)) {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(severity.color)
                    .frame(width: 25, height: 25)
                    .accessibilityHidden(true)
                }
            }
            HStack(spacing: 6) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !history.isEmpty {
                    DashboardSparkline(values: history, fixedMaximum: fixedMaximum, color: severity.color)
                        .frame(width: 52, height: 13)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 79, alignment: .topLeading)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: DashboardDesign.sectionRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(primaryValue)，\(detail)，\(status)")
    }
}
