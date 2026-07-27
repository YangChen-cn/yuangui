import SwiftUI

struct DashboardNetworkMetricRow: View {
    let download: String?
    let upload: String?
    let unavailableText: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(.blue)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(AppLocalizer.string("网络"))
                .font(.caption)
                .bold()
                .frame(width: 34, alignment: .leading)
            if let download, let upload {
                NetworkRateValue(direction: .download, value: download)
                    .frame(maxWidth: .infinity, alignment: .leading)
                NetworkRateValue(direction: .upload, value: upload)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(AppLocalizer.string(unavailableText))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(minHeight: DashboardDesign.rowHeight)
        .contentTransition(.numericText())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let download, let upload else {
            return "\(AppLocalizer.string("网络"))，\(AppLocalizer.string(unavailableText))"
        }
        return "\(AppLocalizer.string("网络"))，\(AppLocalizer.string("下载")) \(download)，\(AppLocalizer.string("上传")) \(upload)"
    }
}

private struct NetworkRateValue: View {
    enum Direction {
        case download
        case upload

        var title: String { AppLocalizer.string(self == .download ? "下载" : "上传") }
        var systemImage: String { self == .download ? "arrow.down" : "arrow.up" }
        var color: Color { self == .download ? .blue : .green }
    }

    let direction: Direction
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: direction.systemImage)
                .foregroundStyle(direction.color)
                .accessibilityHidden(true)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.body)
        .help("\(direction.title)：\(value)")
    }
}
