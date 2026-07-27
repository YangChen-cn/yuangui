import SwiftUI
import UniformTypeIdentifiers

struct DiaryExportView: View {
    @ObservedObject var store: DiaryFeature
    @Environment(\.dismiss) private var dismiss
    @State private var format: ExportFormat = .markdown
    @State private var scope: ExportScope = .all
    @State private var isWorking = false
    @State private var resultURL: URL?
    @State private var errorMessage: String?
    @State private var showRestoreConfirmation = false
    @State private var restoreURL: URL?

    private enum ExportFormat: String, CaseIterable {
        case markdown = "Markdown 阅读版"
        case json = "JSON 数据版"
        case zip = "ZIP 完整导出"
        case backup = "完整备份"

        var fileExtension: String {
            switch self {
            case .markdown: "md"
            case .json: "json"
            case .zip, .backup: "zip"
            }
        }

        var contentType: UTType {
            switch self {
            case .markdown: UTType(filenameExtension: "md") ?? .plainText
            case .json: .json
            case .zip, .backup: .zip
            }
        }
    }

    private enum ExportScope: String, CaseIterable {
        case all = "全部日记"
        case favorites = "仅收藏"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(AppLocalizer.string("导出、备份与恢复"), systemImage: "square.and.arrow.up")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.diaryAccent)
            Picker(AppLocalizer.string("格式"), selection: $format) {
                ForEach(ExportFormat.allCases, id: \.self) { Text(AppLocalizer.string($0.rawValue)).tag($0) }
            }
            .pickerStyle(.menu)
            if format != .backup {
                Picker(AppLocalizer.string("范围"), selection: $scope) {
                    ForEach(ExportScope.allCases, id: \.self) { Text(AppLocalizer.string($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let resultURL {
                VStack(alignment: .leading, spacing: 6) {
                    Label(AppLocalizer.string("操作完成"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(resultURL.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                    Button(AppLocalizer.string("在 Finder 中显示")) { NSWorkspace.shared.activateFileViewerSelecting([resultURL]) }
                }
            }
            Divider()
            HStack {
                Button(AppLocalizer.string("恢复备份…")) {
                    restoreURL = DiaryPanelService.chooseBackup()
                    showRestoreConfirmation = restoreURL != nil
                }
                .disabled(isWorking)
                Spacer()
                Button(AppLocalizer.string("关闭")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(AppLocalizer.string(isWorking ? "处理中…" : "选择位置并导出")) { chooseAndExport() }
                    .buttonStyle(.borderedProminent).disabled(isWorking)
            }
        }
        .padding(20)
        .frame(width: 480)
        .tint(.diaryAccent)
        .confirmationDialog(AppLocalizer.string("恢复会替换当前手账数据"), isPresented: $showRestoreConfirmation) {
            Button(AppLocalizer.string("验证并恢复"), role: .destructive) { restore() }
            Button(AppLocalizer.string("取消"), role: .cancel) { restoreURL = nil }
        } message: {
            Text(AppLocalizer.string("恢复前会完整验证备份；失败时自动回滚当前数据。"))
        }
    }

    private func chooseAndExport() {
        let prefix = AppLocalizer.string(format == .backup ? "手帐本备份" : "手帐本")
        let name = "\(prefix)-\(dateStamp()).\(format.fileExtension)"
        guard let url = DiaryPanelService.saveDestination(suggestedName: name, contentType: format.contentType) else { return }
        isWorking = true
        errorMessage = nil
        resultURL = nil
        Task {
            do {
                let entries = scope == .all ? store.entries : store.entries.filter(\.isFavorite)
                let result: URL
                switch format {
                case .markdown: result = try await store.exportMarkdown(to: url, entries: entries)
                case .json: result = try await store.exportJSON(to: url, entries: entries)
                case .zip: result = try await store.exportZIP(to: url, entries: entries)
                case .backup: result = try await store.backup(to: url)
                }
                resultURL = result
            } catch {
                errorMessage = AppLocalizer.format("diary.export.failed", error.localizedDescription)
            }
            isWorking = false
        }
    }

    private func restore() {
        guard let restoreURL else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await store.restoreBackup(from: restoreURL)
                resultURL = restoreURL
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
            self.restoreURL = nil
        }
    }

    private func dateStamp() -> String {
        Date().formatted(.iso8601.year().month().day().dateSeparator(.omitted))
    }
}
