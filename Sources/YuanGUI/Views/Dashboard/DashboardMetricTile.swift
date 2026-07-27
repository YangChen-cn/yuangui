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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .foregroundStyle(severity.color)
                    .accessibilityHidden(true)
                Text(AppLocalizer.string(title))
                    .font(.caption)
                    .bold()
                Spacer(minLength: 4)
                if !status.isEmpty {
                    Label(AppLocalizer.string(status), systemImage: severityIcon)
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(severity.color)
                }
            }
            Text(primaryValue)
                .font(.title2)
                .bold()
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.12),
                    value: primaryValue
                )
            HStack(spacing: 6) {
                Text(AppLocalizer.string(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !history.isEmpty {
                    DashboardSparkline(
                        values: history,
                        fixedMaximum: fixedMaximum,
                        color: severity == .normal ? Color.accentColor : severity.color
                    )
                        .frame(width: 52, height: 13)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 79, alignment: .topLeading)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: DashboardDesign.sectionRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(AppLocalizer.string(title))，\(primaryValue)，\(AppLocalizer.string(detail))，\(AppLocalizer.string(status))")
    }

    private var severityIcon: String {
        switch severity {
        case .normal: "checkmark"
        case .informational: "info.circle"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}
