import AppKit
import SwiftUI

struct DiaryBackupSettingsView: View {
    @ObservedObject var diary: DiaryFeature

    @State private var resultURL: URL?
    @State private var errorMessage: String?
    @State private var restoreURL: URL?
    @State private var showRestoreConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsDesign.pageSpacing) {
                SettingsPageHeader(
                    title: "手帐本",
                    subtitle: "日记保存在本机，并按每日与每周节奏自动留存",
                    systemImage: "book.closed.fill",
                    accent: .diaryAccent
                )
                statusSection
                actionSection
                feedback
            }
            .padding(.bottom, 8)
        }
        .task {
            await diary.refreshBackupStatus()
        }
        .confirmationDialog("恢复会替换当前手帐数据", isPresented: $showRestoreConfirmation) {
            Button("验证并恢复", role: .destructive, action: restore)
            Button("取消", role: .cancel) { restoreURL = nil }
        } message: {
            Text("恢复前会完整验证备份；失败时自动回滚当前数据。")
        }
    }

    private var statusSection: some View {
        SettingsSectionCard(title: "自动备份", systemImage: "clock.arrow.2.circlepath") {
            LabeledContent("上次自动备份") {
                if let date = diary.backupStatus.lastAutomaticBackup {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                } else {
                    Text("尚未备份")
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("备份数量") {
                Text("\(diary.backupStatus.backupCount) 个")
                    .monospacedDigit()
            }
            Text(
                "每日 \(diary.backupStatus.dailyCount) 个 · 每周 \(diary.backupStatus.weeklyCount) 个"
                    + (diary.backupStatus.manualCount > 0 ? " · 手动 \(diary.backupStatus.manualCount) 个" : "")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("日记发生变化并保存成功后，每天最多自动备份一次；保留最近 7 个每日备份和 4 个每周备份。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionSection: some View {
        SettingsSectionCard(title: "备份与恢复", systemImage: "externaldrive") {
            HStack {
                Button("打开备份文件夹", systemImage: "folder", action: openBackupFolder)
                Button("立即备份", systemImage: "archivebox", action: backupNow)
                    .disabled(diary.isBackupWorking)
                Spacer()
                if diary.isBackupWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Button("从备份恢复…", systemImage: "arrow.counterclockwise", action: chooseRestore)
                .disabled(diary.isBackupWorking)
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if let resultURL {
            Label("已生成 \(resultURL.lastPathComponent)", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private func openBackupFolder() {
        guard let url = diary.backupDirectoryURL else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private func backupNow() {
        errorMessage = nil
        resultURL = nil
        Task {
            do {
                resultURL = try await diary.createBackupNow()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func chooseRestore() {
        restoreURL = DiaryPanelService.chooseBackup()
        showRestoreConfirmation = restoreURL != nil
    }

    private func restore() {
        guard let restoreURL else { return }
        errorMessage = nil
        resultURL = nil
        Task {
            do {
                try await diary.restoreBackup(from: restoreURL)
                resultURL = restoreURL
            } catch {
                errorMessage = error.localizedDescription
            }
            self.restoreURL = nil
        }
    }
}
