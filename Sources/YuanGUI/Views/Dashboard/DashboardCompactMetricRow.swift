import SwiftUI

struct DashboardCompactMetricRow: View {
    let title: String
    let systemImage: String
    let primaryValue: String
    let detail: String
    let status: String
    let severity: DashboardStatusSeverity

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(severity == .normal ? Color.secondary : severity.color)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(AppLocalizer.string(title))
                .font(.caption)
                .bold()
                .frame(width: 34, alignment: .leading)
            Text(AppLocalizer.string(primaryValue))
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(AppLocalizer.string(detail))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
            if !status.isEmpty {
                Label(AppLocalizer.string(status), systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(severity.color)
            }
        }
        .frame(minHeight: DashboardDesign.rowHeight)
        .contentTransition(.numericText())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [title, primaryValue, detail, status]
                .filter { !$0.isEmpty }
                .joined(separator: "，")
        )
    }
}
