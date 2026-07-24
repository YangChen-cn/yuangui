import SwiftUI

/// 导出视图
struct DiaryExportView: View {
    @ObservedObject var store: DiaryFeature
    @Environment(\.dismiss) private var dismiss

    @State private var exportFormat: ExportFormat = .markdown
    @State private var exportScope: ExportScope = .all
    @State private var isExporting = false
    @State private var exportResult: ExportResult?
    @State private var errorMessage: String?

    private enum ExportFormat: String, CaseIterable {
        case markdown = "Markdown"
        case json = "JSON"
        case zip = "ZIP（含附件）"
    }

    private enum ExportScope: String, CaseIterable {
        case all = "全部日记"
        case favorites = "仅收藏"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导出手账")
                .font(.system(size: 16, weight: .bold, design: .rounded))

            // 格式选择
            Picker("格式", selection: $exportFormat) {
                ForEach(ExportFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            // 范围选择
            Picker("范围", selection: $exportScope) {
                ForEach(ExportScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            if let result = exportResult {
                VStack(alignment: .leading, spacing: 6) {
                    Label("导出成功", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(result.url.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([result.url])
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isExporting ? "导出中…" : "导出") { performExport() }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .disabled(isExporting)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func performExport() {
        isExporting = true
        errorMessage = nil
        exportResult = nil

        Task {
            let entries = exportScope == .all ? store.entries : store.entries.filter(\.isFavorite)
            let exportService = store.exportService()

            do {
                let url: URL
                switch exportFormat {
                case .markdown:
                    url = try exportService.exportMarkdown(entries: entries)
                case .json:
                    url = try exportService.exportJSON(entries: entries)
                case .zip:
                    url = try exportService.exportZIP(entries: entries)
                }
                exportResult = ExportResult(url: url)
            } catch {
                errorMessage = "导出失败：\(error.localizedDescription)"
            }
            isExporting = false
        }
    }
}

private struct ExportResult {
    let url: URL
}
