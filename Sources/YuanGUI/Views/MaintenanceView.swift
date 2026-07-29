import AppKit
import SwiftUI

struct MaintenanceView: View {
    @ObservedObject var store: MaintenanceStore
    @State private var expandedApplications: Set<UUID> = []
    @State private var showsInstallerPermissionExplanation = false

    var body: some View {
        VStack(spacing: MaintenanceDesign.sectionSpacing) {
            MaintenanceHeroView(store: store)
            MaintenanceTabBar(selection: $store.selectedTab)

            Group {
                if store.selectedTab == 0 { cleanupPage }
                else if store.selectedTab == 1 { uninstallPage }
                else { operationsPage }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(MaintenanceDesign.outerPadding)
        .frame(minWidth: 760, minHeight: 570)
        .background(.clear)
    }

    private var commonToolbar: some View {
        HStack(spacing: 8) {
            TextField(AppLocalizer.string("搜索名称、路径或 bundle ID"), text: $store.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 340)
            Picker(AppLocalizer.string("排序"), selection: $store.sortOrder) {
                ForEach(MaintenanceStore.SortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .frame(width: 140)
        }
    }

    private var cleanupPage: some View {
        VStack(spacing: 10) {
            cleanupToolbar

            if store.cleanupCandidates.isEmpty {
                ContentUnavailableView {
                    Label(AppLocalizer.string("maintenance.welcome.title"), systemImage: "sparkles")
                } description: {
                    Text(AppLocalizer.string("maintenance.welcome.description"))
                } actions: {
                    Button(AppLocalizer.string("maintenance.welcome.start")) {
                        Task { await store.scanCleanup() }
                    }
                    .yuanSystemGlassButton(isProminent: true)
                    .disabled(store.isScanning || store.isWorking)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .yuanLiquidGlassSurface(.clear, cornerRadius: MaintenanceDesign.cardRadius)
            } else {
                List {
                    Section(AppLocalizer.string("分类摘要")) {
                        ForEach(CleanupCategory.allCases, id: \.self) { category in
                            let values = store.cleanupCandidates.filter { $0.category == category }
                            if !values.isEmpty {
                                HStack {
                                    Text(category.title)
                                    Spacer()
                                    Text(AppLocalizer.format("maintenance.ui.itemCountSize", values.count, size(values.reduce(0) { $0 + $1.byteCount })))
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                        }
                    }
                    ForEach(MaintenanceRisk.allCases, id: \.self) { risk in
                        let candidates = store.visibleCleanupCandidates.filter { $0.risk == risk }
                        if !candidates.isEmpty {
                            Section(AppLocalizer.format("maintenance.ui.riskCount", risk.title, candidates.count)) {
                                ForEach(candidates) { candidate in cleanupRow(candidate) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .yuanLiquidGlassSurface(.regular, cornerRadius: MaintenanceDesign.cardRadius)
            }
        }
    }

    private var cleanupToolbar: some View {
        MaintenanceCommandSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    scanCleanupButton
                    Button(AppLocalizer.string("全选推荐项")) { store.selectRecommendedCleanup() }
                        .yuanSystemGlassButton()
                        .disabled(store.cleanupCandidates.isEmpty || store.isWorking)
                    Spacer(minLength: 8)
                    selectedCleanupSize
                    startCleanupButton
                }
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 9) {
                        commonToolbar
                        Spacer(minLength: 8)
                        whitelistMenu
                        scanScopeMenu
                    }
                    HStack(spacing: 9) {
                        commonToolbar
                        Spacer(minLength: 8)
                        compactOptionsMenu
                    }
                }
            }
        }
    }

    private var compactOptionsMenu: some View {
        Menu {
            Button(AppLocalizer.string("全选推荐项")) { store.selectRecommendedCleanup() }
                .disabled(store.cleanupCandidates.isEmpty || store.isWorking)
            Divider()
            whitelistMenu
            scanScopeMenu
        } label: {
            Label(AppLocalizer.string("maintenance.ui.options"), systemImage: "slider.horizontal.3")
        }
        .yuanSystemGlassButton()
    }

    private var scanCleanupButton: some View {
        Button(AppLocalizer.string("扫描可清理空间")) { Task { await store.scanCleanup() } }
            .yuanSystemGlassButton(isProminent: true)
            .disabled(store.isScanning || store.isWorking)
    }

    private var startCleanupButton: some View {
        Button(AppLocalizer.string("开始清理…")) { confirmCleanup() }
            .yuanSystemGlassButton(isProminent: true)
            .disabled(store.selectedCleanupIDs.isEmpty || store.isWorking)
    }

    private var selectedCleanupSize: some View {
        Text(AppLocalizer.format("maintenance.ui.selectedSize", size(store.selectedCleanupBytes)))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .layoutPriority(1)
    }

    private var whitelistMenu: some View {
        Menu {
            if store.whitelistedPaths.isEmpty {
                Text(AppLocalizer.string("白名单为空"))
            } else {
                ForEach(store.whitelistedPaths, id: \.self) { path in
                    Button(AppLocalizer.format("maintenance.remove", URL(fileURLWithPath: path).lastPathComponent)) {
                        store.removeFromWhitelist(path)
                    }
                }
                Divider()
                Button(AppLocalizer.string("清空白名单"), role: .destructive) { store.clearWhitelist() }
            }
        } label: {
            Label(AppLocalizer.string("白名单"), systemImage: "hand.raised")
        }
        .yuanSystemGlassButton()
    }

    private var scanScopeMenu: some View {
        Menu {
            Section(AppLocalizer.string("扫描类别")) {
                ForEach(CleanupCategory.allCases, id: \.self) { category in
                    Toggle(category.title, isOn: Binding(
                        get: { store.enabledCleanupCategories.contains(category) },
                        set: { enabled in
                            if category == .oldInstallerPackage,
                               enabled,
                               !store.enabledCleanupCategories.contains(category) {
                                showsInstallerPermissionExplanation = true
                            } else {
                                store.setCategory(category, enabled: enabled)
                            }
                        }
                    ))
                }
            }
            Section(AppLocalizer.string("项目扫描位置")) {
                if store.projectScanRoots.isEmpty {
                    Text(AppLocalizer.string("未设置项目目录"))
                } else {
                    ForEach(store.projectScanRoots, id: \.self) { path in
                        Button(AppLocalizer.format("maintenance.remove", URL(fileURLWithPath: path).lastPathComponent)) {
                            store.removeProjectScanRoot(path)
                        }
                    }
                }
                Divider()
                Button(AppLocalizer.string("添加项目目录…")) { chooseProjectRoot() }
            }
            Text(AppLocalizer.string("项目产物和旧安装包默认不选，并只会移入废纸篓。"))
        } label: {
            Label(AppLocalizer.string("扫描范围"), systemImage: "folder.badge.gearshape")
        }
        .yuanSystemGlassButton()
        .alert(
            AppLocalizer.string("maintenance.installerPermission.title"),
            isPresented: $showsInstallerPermissionExplanation
        ) {
            Button(AppLocalizer.string("maintenance.installerPermission.enable")) {
                store.setCategory(.oldInstallerPackage, enabled: true)
            }
            Button(AppLocalizer.string("取消"), role: .cancel) { }
        } message: {
            Text(AppLocalizer.string("maintenance.installerPermission.message"))
        }
    }

    private func chooseProjectRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = AppLocalizer.string("添加")
        if panel.runModal() == .OK, let url = panel.url {
            store.addProjectScanRoot(url)
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
                    Text(candidate.displayName)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(candidate.confidence.title).font(.caption2).foregroundStyle(.secondary)
                }
                Text(AppLocalizer.string(candidate.reason))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(candidate.url.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(size(candidate.byteCount)).monospacedDigit()
                if let date = candidate.modifiedAt {
                    Text(date, style: .date).font(.caption2).foregroundStyle(.secondary)
                }
                Text(AppLocalizer.string(candidate.disposition == .permanent ? "永久释放" : "清空废纸篓后释放"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(MaintenanceDesign.rowPadding)
        .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: MaintenanceDesign.rowRadius))
        .contextMenu { Button(AppLocalizer.string("永不清理此项目")) { store.addToWhitelist(candidate) } }
    }

    private var uninstallPage: some View {
        VStack(spacing: 10) {
            MaintenanceCommandSurface {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 9) {
                        Button(AppLocalizer.string("扫描已安装软件")) { Task { await store.scanApplications() } }
                            .yuanSystemGlassButton(isProminent: true)
                            .disabled(store.isScanning || store.isWorking)
                        Spacer(minLength: 8)
                        Text(AppLocalizer.format("maintenance.ui.selectedSize", size(store.selectedUninstallBytes)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                        Button(AppLocalizer.string("移入废纸篓…")) { confirmUninstall() }
                            .yuanSystemGlassButton(isProminent: true)
                            .disabled(store.selectedApplicationIDs.isEmpty || store.isWorking)
                    }
                    Divider()
                    commonToolbar
                }
            }

            if store.applications.isEmpty {
                ContentUnavailableView(
                    AppLocalizer.string("等待扫描"),
                    systemImage: "shippingbox",
                    description: Text(AppLocalizer.string("系统应用、共享数据与受管理软件会自动受到保护"))
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .yuanLiquidGlassSurface(.clear, cornerRadius: MaintenanceDesign.cardRadius)
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
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .yuanLiquidGlassSurface(.regular, cornerRadius: MaintenanceDesign.cardRadius)
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
                    Text(application.name)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if application.removalBlocked {
                        Label(AppLocalizer.string("受保护"), systemImage: "lock.fill").font(.caption).foregroundStyle(.orange)
                    }
                }
                Text("\(application.bundleIdentifier) · \(application.source.title) · \(application.management.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let warning = application.warnings.first {
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)
            Spacer()
            VStack(alignment: .trailing) {
                Text(size(application.reclaimableByteCount)).monospacedDigit()
                Text(AppLocalizer.format("maintenance.ui.componentCount", application.components.count)).font(.caption2).foregroundStyle(.secondary)
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
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                Text(AppLocalizer.string(component.reason))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(component.url.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer()
            Text(size(component.byteCount)).font(.caption).monospacedDigit()
        }
        .padding(.leading, 28)
        .padding(.vertical, 7)
    }

    private var operationsPage: some View {
        VStack(spacing: 8) {
            HStack {
                Text(AppLocalizer.string("所有逐项记录仅保存在本机")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(AppLocalizer.string("打开废纸篓")) { store.openTrash() }
                    .yuanSystemGlassButton()
            }
            if store.operations.isEmpty {
                ContentUnavailableView(AppLocalizer.string("还没有清理记录"), systemImage: "clock")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .yuanLiquidGlassSurface(.clear, cornerRadius: MaintenanceDesign.cardRadius)
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
                            Label(
                                AppLocalizer.format("maintenance.activity.permanent", size(operation.permanentlyDeletedBytes ?? 0)),
                                systemImage: "sparkles"
                            )
                            Label(
                                AppLocalizer.format("maintenance.activity.trash", size(operation.trashedBytes ?? 0)),
                                systemImage: "trash"
                            )
                            Text(
                                AppLocalizer.format(
                                    "maintenance.activity.summary",
                                    operation.itemCount,
                                    operation.skipped.count,
                                    operation.errors.count
                                )
                            )
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        ForEach(Array((operation.results ?? []).filter { $0.outcome == .skipped || $0.outcome == .failed }.prefix(3))) { result in
                            Text(
                                AppLocalizer.format(
                                    "maintenance.activity.detail",
                                    result.displayName,
                                    result.message ?? outcomeTitle(result.outcome)
                                )
                            )
                                .font(.caption2)
                                .foregroundStyle(result.outcome == .failed ? .red : .orange)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(MaintenanceDesign.rowPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: MaintenanceDesign.rowRadius))
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .yuanLiquidGlassSurface(.regular, cornerRadius: MaintenanceDesign.cardRadius)
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
        alert.messageText = AppLocalizer.string("让元圭和 VCC 开始清理？")
        alert.informativeText = AppLocalizer.format(
            "maintenance.confirm.cleanup.message",
            permanentItems.count,
            size(permanentBytes),
            trashItems.count,
            size(trashBytes)
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppLocalizer.string("开始清理"))
        alert.addButton(withTitle: AppLocalizer.string("取消"))
        if alert.runModal() == .alertFirstButtonReturn { Task { await store.cleanSelected() } }
    }

    private func confirmUninstall() {
        let names = store.selectedApplications.map(\.name).joined(separator: AppLocalizer.string("maintenance.list.separator"))
        let alert = NSAlert()
        alert.messageText = AppLocalizer.string("把这些软件移入废纸篓？")
        alert.informativeText = AppLocalizer.format("maintenance.confirm.uninstall.message", names, size(store.selectedUninstallBytes))
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppLocalizer.string("移入废纸篓"))
        alert.addButton(withTitle: AppLocalizer.string("取消"))
        if alert.runModal() == .alertFirstButtonReturn { Task { await store.uninstallSelected() } }
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func outcomeTitle(_ outcome: MaintenanceItemResult.Outcome) -> String {
        switch outcome {
        case .deleted: return AppLocalizer.string("已永久删除")
        case .trashed: return AppLocalizer.string("已移入废纸篓")
        case .skipped: return AppLocalizer.string("已跳过")
        case .failed: return AppLocalizer.string("失败")
        }
    }
}
