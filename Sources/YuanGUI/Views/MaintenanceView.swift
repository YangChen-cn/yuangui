import AppKit
import SwiftUI

struct MaintenanceView: View {
    @ObservedObject var store: MaintenanceStore
    var body: some View {
        VStack(spacing: 12) {
            maintenanceBubble
            Picker("清理分类", selection: $store.selectedTab) {
                Label("空间清理", systemImage: "sparkles").tag(0)
                Label("软件卸载", systemImage: "shippingbox").tag(1)
                Label("操作记录", systemImage: "clock.arrow.circlepath").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden()
            Group {
                if store.selectedTab == 0 { cleanupPage }
                else if store.selectedTab == 1 { uninstallPage }
                else { operationsPage }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 540)
        .background(.regularMaterial)
    }

    private var maintenanceBubble: some View {
        HStack(spacing: 12) {
            Image(systemName: store.isScanning ? "cat.fill" : "heart.circle.fill")
                .font(.system(size: 28, weight: .bold)).foregroundStyle(.pink)
                .symbolEffect(.bounce, value: store.message)
            Text(store.message).font(.system(size: 14, weight: .bold, design: .rounded))
            Spacer()
            if store.isScanning || store.isWorking { ProgressView().controlSize(.small) }
        }
        .padding(14)
        .background(LinearGradient(colors: [.pink.opacity(0.16), .purple.opacity(0.10)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.55)))
    }

    private var cleanupPage: some View {
        VStack(spacing: 10) {
            HStack {
                Button("扫描可清理空间") { Task { await store.scanCleanup() } }
                    .buttonStyle(.borderedProminent).tint(.pink).disabled(store.isScanning || store.isWorking)
                Spacer()
                Text("已选 \(ByteCountFormatter.string(fromByteCount: store.selectedCleanupBytes, countStyle: .file))")
                    .font(.caption).foregroundStyle(.secondary)
                Menu {
                    if store.whitelistedPaths.isEmpty {
                        Text("白名单为空")
                    } else {
                        ForEach(store.whitelistedPaths, id: \.self) { path in
                            Button("移除：\(URL(fileURLWithPath: path).lastPathComponent)") {
                                store.removeFromWhitelist(path)
                            }
                        }
                        Divider()
                        Button("清空白名单", role: .destructive) { store.clearWhitelist() }
                    }
                } label: {
                    Label("白名单", systemImage: "hand.raised")
                }
                Button("开始清理…") { confirmCleanup() }
                    .disabled(store.selectedCleanupIDs.isEmpty || store.isWorking)
            }
            if store.cleanupCandidates.isEmpty {
                ContentUnavailableView("等待扫描", systemImage: "sparkles", description: Text("只扫描当前用户的安全缓存与残留目录"))
            } else {
                List(store.cleanupCandidates) { candidate in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { store.selectedCleanupIDs.contains(candidate.id) },
                            set: { value in
                                if value { store.selectedCleanupIDs.insert(candidate.id) }
                                else { store.selectedCleanupIDs.remove(candidate.id) }
                            }
                        )).labelsHidden()
                        Image(systemName: candidate.disposition == .permanent ? "sparkles" : "trash")
                            .foregroundStyle(candidate.disposition == .permanent ? .orange : .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.displayName).lineLimit(1)
                            Text("\(candidate.category.title) · \(candidate.disposition == .permanent ? "永久清理" : "移入废纸篓")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: candidate.byteCount, countStyle: .file)).monospacedDigit()
                    }
                    .contextMenu { Button("永不清理此项目") { store.addToWhitelist(candidate) } }
                }
            }
        }
    }

    private var uninstallPage: some View {
        VStack(spacing: 10) {
            HStack {
                Button("扫描已安装软件") { Task { await store.scanApplications() } }
                    .buttonStyle(.borderedProminent).tint(.pink).disabled(store.isScanning || store.isWorking)
                Spacer()
                Button("移入废纸篓…") { confirmUninstall() }
                    .disabled(store.selectedApplicationIDs.isEmpty || store.isWorking)
            }
            if store.applications.isEmpty {
                ContentUnavailableView("等待扫描", systemImage: "shippingbox", description: Text("系统应用与桌宠自身会自动受到保护"))
            } else {
                List(store.applications) { app in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { store.selectedApplicationIDs.contains(app.id) },
                            set: { value in
                                if value { store.selectedApplicationIDs.insert(app.id) }
                                else { store.selectedApplicationIDs.remove(app.id) }
                            }
                        )).labelsHidden()
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).font(.headline)
                            Text("\(app.bundleIdentifier) · \(app.residuals.count) 项用户级残留")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: app.byteCount, countStyle: .file)).monospacedDigit()
                    }
                }
            }
        }
    }

    private var operationsPage: some View {
        VStack(spacing: 8) {
            HStack {
                Text("所有操作仅保存在本机").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("打开废纸篓") { store.openTrash() }
            }
            Group {
                if store.operations.isEmpty {
                    ContentUnavailableView("还没有清理记录", systemImage: "clock")
                } else {
                    List(store.operations) { operation in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Label(operation.title, systemImage: operation.kind == .cleanup ? "sparkles" : "shippingbox")
                                    .font(.headline)
                                Spacer()
                                Text(operation.date, style: .date).foregroundStyle(.secondary)
                                Text(operation.date, style: .time).foregroundStyle(.secondary)
                            }
                            Text("处理 \(operation.itemCount) 项 · \(ByteCountFormatter.string(fromByteCount: operation.reclaimedBytes, countStyle: .file))")
                            if let error = operation.errors.first { Text(error).font(.caption).foregroundStyle(.red) }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .onAppear { store.refreshOperations() }
    }

    private func confirmCleanup() {
        let selected = store.selectedCleanup
        let permanent = selected.filter { $0.disposition == .permanent }.count
        let recyclable = selected.count - permanent
        let alert = NSAlert()
        alert.messageText = "让元圭和 VCC 开始清理？"
        alert.informativeText = "\(permanent) 项缓存将永久删除，\(recyclable) 项残留会移入废纸篓。预计处理 \(ByteCountFormatter.string(fromByteCount: store.selectedCleanupBytes, countStyle: .file))。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "开始清理")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { Task { await store.cleanSelected() } }
    }

    private func confirmUninstall() {
        let names = store.selectedApplications.map(\.name).joined(separator: "、")
        let alert = NSAlert()
        alert.messageText = "把这些软件移入废纸篓？"
        alert.informativeText = "\(names)\n应用本体和可确认的用户级残留将移入废纸篓，不会永久删除。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移入废纸篓")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { Task { await store.uninstallSelected() } }
    }
}
