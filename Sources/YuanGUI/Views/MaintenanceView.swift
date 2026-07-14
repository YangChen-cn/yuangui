import AppKit
import SwiftUI

struct MaintenanceView: View {
    @ObservedObject var store: MaintenanceStore
    @State private var expandedApplications: Set<UUID> = []

    var body: some View {
        VStack(spacing: 12) {
            maintenanceBubble
            Picker("清理分类", selection: $store.selectedTab) {
                Label("空间清理", systemImage: "sparkles").tag(0)
                Label("软件卸载", systemImage: "shippingbox").tag(1)
                Label("操作记录", systemImage: "clock.arrow.circlepath").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                if store.selectedTab == 0 { cleanupPage }
                else if store.selectedTab == 1 { uninstallPage }
                else { operationsPage }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 570)
        .background(.regularMaterial)
    }

    private var maintenanceBubble: some View {
        VStack(spacing: 7) {
            HStack(spacing: 12) {
                Image(systemName: store.isScanning ? "cat.fill" : "heart.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.pink)
                    .symbolEffect(.bounce, value: store.message)
                Text(store.message).font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                if store.isScanning || store.isWorking { ProgressView().controlSize(.small) }
            }
            if let progress = store.scanProgress, progress.total > 0 {
                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    .tint(.pink)
            }
        }
        .padding(14)
        .background(
            LinearGradient(colors: [.pink.opacity(0.16), .purple.opacity(0.10)], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.55)))
    }

    private var commonToolbar: some View {
        HStack(spacing: 8) {
            TextField("搜索名称、路径或 bundle ID", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 270)
            Picker("排序", selection: $store.sortOrder) {
                ForEach(MaintenanceStore.SortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .frame(width: 125)
        }
    }

    private var cleanupPage: some View {
        VStack(spacing: 10) {
            HStack {
                Button("扫描可清理空间") { Task { await store.scanCleanup() } }
                    .buttonStyle(.borderedProminent).tint(.pink)
                    .disabled(store.isScanning || store.isWorking)
                Button("全选推荐项") { store.selectRecommendedCleanup() }
                    .disabled(store.cleanupCandidates.isEmpty || store.isWorking)
                commonToolbar
                Spacer()
                Text("已选 \(size(store.selectedCleanupBytes))")
                    .font(.caption).foregroundStyle(.secondary)
                whitelistMenu
                Button("开始清理…") { confirmCleanup() }
                    .disabled(store.selectedCleanupIDs.isEmpty || store.isWorking)
            }

            if store.cleanupCandidates.isEmpty {
                ContentUnavailableView("等待扫描", systemImage: "sparkles", description: Text("只扫描当前用户的安全缓存与残留目录"))
            } else {
                List {
                    ForEach(MaintenanceRisk.allCases, id: \.self) { risk in
                        let candidates = store.visibleCleanupCandidates.filter { $0.risk == risk }
                        if !candidates.isEmpty {
                            Section("\(risk.title) · \(candidates.count) 项") {
                                ForEach(candidates) { candidate in cleanupRow(candidate) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var whitelistMenu: some View {
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
    }

    private func cleanupRow(_ candidate: CleanupCandidate) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { store.selectedCleanupIDs.contains(candidate.id) },
                set: { value in
                    if value { store.selectedCleanupIDs.insert(candidate.id) }
                    else { store.selectedCleanupIDs.remove(candidate.id) }
                }
            ))
            .labelsHidden()
            .disabled(candidate.risk == .protected)
            Image(systemName: candidate.disposition == .permanent ? "sparkles" : "trash")
                .foregroundStyle(candidate.disposition == .permanent ? .orange : .blue)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(candidate.displayName).font(.headline).lineLimit(1)
                    Text(candidate.confidence.title).font(.caption2).foregroundStyle(.secondary)
                }
                Text(candidate.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(candidate.url.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(size(candidate.byteCount)).monospacedDigit()
                if let date = candidate.modifiedAt {
                    Text(date, style: .date).font(.caption2).foregroundStyle(.secondary)
                }
                Text(candidate.disposition == .permanent ? "永久释放" : "清空废纸篓后释放")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contextMenu { Button("永不清理此项目") { store.addToWhitelist(candidate) } }
    }

    private var uninstallPage: some View {
        VStack(spacing: 10) {
            HStack {
                Button("扫描已安装软件") { Task { await store.scanApplications() } }
                    .buttonStyle(.borderedProminent).tint(.pink)
                    .disabled(store.isScanning || store.isWorking)
                commonToolbar
                Spacer()
                Text("已选 \(size(store.selectedUninstallBytes))")
                    .font(.caption).foregroundStyle(.secondary)
                Button("移入废纸篓…") { confirmUninstall() }
                    .disabled(store.selectedApplicationIDs.isEmpty || store.isWorking)
            }

            if store.applications.isEmpty {
                ContentUnavailableView("等待扫描", systemImage: "shippingbox", description: Text("系统应用、共享数据与受管理软件会自动受到保护"))
            } else {
                List {
                    ForEach(store.visibleApplications) { application in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedApplications.contains(application.id) },
                                set: { expanded in
                                    if expanded { expandedApplications.insert(application.id) }
                                    else { expandedApplications.remove(application.id) }
                                }
                            )
                        ) {
                            ForEach(application.components) { component in
                                componentRow(component, in: application)
                            }
                        } label: {
                            applicationRow(application)
                        }
                    }
                }
            }
        }
    }

    private func applicationRow(_ application: ApplicationCandidate) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { store.selectedApplicationIDs.contains(application.id) },
                set: { store.setApplicationSelected(application, selected: $0) }
            ))
            .labelsHidden()
            .disabled(application.removalBlocked)
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                .resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(application.name).font(.headline)
                    if application.removalBlocked {
                        Label("受保护", systemImage: "lock.fill").font(.caption).foregroundStyle(.orange)
                    }
                }
                Text("\(application.bundleIdentifier) · \(application.source.title) · \(application.management.title)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let warning = application.warnings.first {
                    Text(warning).font(.caption2).foregroundStyle(.orange).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(size(application.reclaimableByteCount)).monospacedDigit()
                Text("\(application.components.count) 个组件").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func componentRow(_ component: UninstallComponent, in application: ApplicationCandidate) -> some View {
        HStack(spacing: 9) {
            Toggle("", isOn: Binding(
                get: { store.selectedUninstallComponentIDs.contains(component.id) },
                set: { store.setComponentSelected(component, in: application, selected: $0) }
            ))
            .labelsHidden()
            .disabled(component.risk == .protected || application.removalBlocked || component.kind == .application)
            Image(systemName: component.risk == .protected ? "lock.shield" : "doc")
                .foregroundStyle(component.risk == .protected ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(component.kind.title) · \(component.risk.title) · \(component.confidence.title)")
                    .font(.caption).fontWeight(.medium)
                Text(component.reason).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(component.url.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            Text(size(component.byteCount)).font(.caption).monospacedDigit()
        }
        .padding(.leading, 28)
    }

    private var operationsPage: some View {
        VStack(spacing: 8) {
            HStack {
                Text("所有逐项记录仅保存在本机").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("打开废纸篓") { store.openTrash() }
            }
            if store.operations.isEmpty {
                ContentUnavailableView("还没有清理记录", systemImage: "clock")
            } else {
                List(store.operations) { operation in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(operation.title, systemImage: operation.kind == .cleanup ? "sparkles" : "shippingbox")
                                .font(.headline)
                            Spacer()
                            Text(operation.date, style: .date).foregroundStyle(.secondary)
                            Text(operation.date, style: .time).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 16) {
                            Label("永久释放 \(size(operation.permanentlyDeletedBytes ?? 0))", systemImage: "sparkles")
                            Label("废纸篓 \(size(operation.trashedBytes ?? 0))", systemImage: "trash")
                            Text("成功 \(operation.itemCount) · 跳过 \(operation.skipped.count) · 失败 \(operation.errors.count)")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        ForEach(Array((operation.results ?? []).filter { $0.outcome == .skipped || $0.outcome == .failed }.prefix(3))) { result in
                            Text("\(result.displayName)：\(result.message ?? outcomeTitle(result.outcome))")
                                .font(.caption2)
                                .foregroundStyle(result.outcome == .failed ? .red : .orange)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear { store.refreshOperations() }
    }

    private func confirmCleanup() {
        let selected = store.selectedCleanup
        let permanentItems = selected.filter { $0.disposition == .permanent }
        let trashItems = selected.filter { $0.disposition == .recycle }
        let permanentBytes = permanentItems.reduce(0) { $0 + $1.byteCount }
        let trashBytes = trashItems.reduce(0) { $0 + $1.byteCount }
        let alert = NSAlert()
        alert.messageText = "让元圭和 VCC 开始清理？"
        alert.informativeText = "永久删除：\(permanentItems.count) 项，预计释放 \(size(permanentBytes))。\n移入废纸篓：\(trashItems.count) 项，清空后可释放 \(size(trashBytes))。\n状态变化、符号链接或越界路径会自动跳过。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "开始清理")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { Task { await store.cleanSelected() } }
    }

    private func confirmUninstall() {
        let names = store.selectedApplications.map(\.name).joined(separator: "、")
        let alert = NSAlert()
        alert.messageText = "把这些软件移入废纸篓？"
        alert.informativeText = "\(names)\n所选应用本体和用户级组件共约 \(size(store.selectedUninstallBytes))，将统一移入废纸篓。受保护、共享或扫描后发生变化的项目会跳过。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "移入废纸篓")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { Task { await store.uninstallSelected() } }
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func outcomeTitle(_ outcome: MaintenanceItemResult.Outcome) -> String {
        switch outcome {
        case .deleted: return "已永久删除"
        case .trashed: return "已移入废纸篓"
        case .skipped: return "已跳过"
        case .failed: return "失败"
        }
    }
}
