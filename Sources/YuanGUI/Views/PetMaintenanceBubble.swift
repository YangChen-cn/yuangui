import SwiftUI

struct PetMaintenanceBubble: View {
    @ObservedObject var store: MaintenanceStore
    @State private var expandedApplicationID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let progress = store.scanProgress, progress.total > 0 {
                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    .tint(.pink)
            }

            if !store.isScanning && !store.isWorking && !store.quickCompleted {
                if store.quickMode == .cleanup { cleanupResults }
                else if store.quickMode == .uninstall { uninstallResults }
            }

            if store.quickCompleted {
                HStack {
                    Button("查看操作记录") { store.openFullMaintenance(tab: 2) }
                    Spacer()
                    Button("好呀～") { store.dismissQuick() }
                        .buttonStyle(.borderedProminent).tint(.pink)
                }
            }
        }
        .padding(14)
        .frame(width: 450)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(
            LinearGradient(colors: [.pink.opacity(0.12), .blue.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.72), lineWidth: 0.9))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 7)
        .overlay(alignment: .bottom) {
            MaintenanceBubbleTail().fill(.regularMaterial).frame(width: 22, height: 11).offset(y: 8)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: store.quickMode == .cleanup ? "sparkles" : "shippingbox.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.pink)
            Text(store.message)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .lineLimit(2)
            Spacer()
            if store.isScanning || store.isWorking { ProgressView().controlSize(.small) }
            Button { store.dismissQuick() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    private var cleanupResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.cleanupCandidates.isEmpty {
                Text("没有发现需要清理的内容～").foregroundStyle(.secondary)
                emptyFooter(tab: 0)
            } else {
                cleanupSummary
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(MaintenanceRisk.allCases, id: \.self) { risk in
                            let candidates = store.cleanupCandidates.filter { $0.risk == risk }
                            if !candidates.isEmpty {
                                HStack {
                                    riskBadge(risk)
                                    Text("\(candidates.count) 项")
                                        .font(.system(size: 9.5, design: .rounded)).foregroundStyle(.secondary)
                                }
                                ForEach(Array(candidates.prefix(4))) { candidate in
                                    cleanupCandidateRow(candidate)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 188)

                HStack {
                    Button("全选推荐") { store.selectRecommendedCleanup() }
                    Button("打开完整清理屋") { store.openFullMaintenance(tab: 0) }
                    Spacer()
                    Button("确认清理") { Task { await store.cleanSelected() } }
                        .buttonStyle(.borderedProminent).tint(.pink)
                        .disabled(store.selectedCleanupIDs.isEmpty)
                }
            }
        }
    }

    private var cleanupSummary: some View {
        let permanent = store.selectedCleanup.filter { $0.disposition == .permanent }
        let trash = store.selectedCleanup.filter { $0.disposition == .recycle }
        return HStack(spacing: 12) {
            Label("永久释放 \(size(permanent.reduce(0) { $0 + $1.byteCount }))", systemImage: "sparkles")
            Label("废纸篓 \(size(trash.reduce(0) { $0 + $1.byteCount }))", systemImage: "trash")
            Spacer()
        }
        .font(.system(size: 9.5, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }

    private func cleanupCandidateRow(_ candidate: CleanupCandidate) -> some View {
        Toggle(isOn: Binding(
            get: { store.selectedCleanupIDs.contains(candidate.id) },
            set: { selected in
                if selected { store.selectedCleanupIDs.insert(candidate.id) }
                else { store.selectedCleanupIDs.remove(candidate.id) }
            }
        )) {
            HStack(spacing: 7) {
                Image(systemName: candidate.disposition == .permanent ? "sparkles" : "trash")
                    .foregroundStyle(candidate.disposition == .permanent ? .orange : .blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.displayName).font(.system(size: 10.5, weight: .semibold, design: .rounded)).lineLimit(1)
                    Text("\(candidate.category.title) · \(candidate.reason)")
                        .font(.system(size: 8.5, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(size(candidate.byteCount)).font(.system(size: 9.5, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(candidate.risk == .protected)
    }

    private var uninstallResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.applications.isEmpty {
                Text("没有发现可列出的第三方软件～").foregroundStyle(.secondary)
                emptyFooter(tab: 1)
            } else {
                HStack {
                    Label("已选 \(store.selectedApplications.count) 个应用", systemImage: "checkmark.circle")
                    Text("约 \(size(store.selectedUninstallBytes))")
                    Spacer()
                    Text("展开可逐组件选择").foregroundStyle(.secondary)
                }
                .font(.system(size: 9.5, weight: .medium, design: .rounded))

                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(Array(store.visibleApplications.prefix(6))) { application in
                            applicationCard(application)
                        }
                    }
                }
                .frame(maxHeight: 218)

                HStack {
                    Button("打开完整清理屋") { store.openFullMaintenance(tab: 1) }
                    Spacer()
                    Button("确认移入废纸篓") { Task { await store.uninstallSelected() } }
                        .buttonStyle(.borderedProminent).tint(.pink)
                        .disabled(store.selectedApplicationIDs.isEmpty)
                }
            }
        }
    }

    private func applicationCard(_ application: ApplicationCandidate) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Toggle("", isOn: Binding(
                    get: { store.selectedApplicationIDs.contains(application.id) },
                    set: { store.setApplicationSelected(application, selected: $0) }
                ))
                .labelsHidden().toggleStyle(.checkbox)
                .disabled(application.removalBlocked)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(application.name).font(.system(size: 10.5, weight: .semibold, design: .rounded)).lineLimit(1)
                        if application.removalBlocked { riskBadge(.protected) }
                        else if application.components.contains(where: { $0.risk == .review }) { riskBadge(.review) }
                    }
                    Text("\(application.management.title) · \(application.components.count) 个组件")
                        .font(.system(size: 8.5, design: .rounded)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(size(application.reclaimableByteCount))
                    .font(.system(size: 9.5, design: .rounded)).foregroundStyle(.secondary)
                Button {
                    expandedApplicationID = expandedApplicationID == application.id ? nil : application.id
                } label: {
                    Image(systemName: expandedApplicationID == application.id ? "chevron.up.circle" : "chevron.down.circle")
                }
                .buttonStyle(.plain)
            }

            if let warning = application.warnings.first {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 8.5, design: .rounded)).foregroundStyle(.orange).lineLimit(2)
            }

            if expandedApplicationID == application.id {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(application.components.prefix(6))) { component in
                        componentRow(component, in: application)
                    }
                }
                .padding(.leading, 21)
            }
        }
        .padding(7)
        .background(.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 10))
    }

    private func componentRow(_ component: UninstallComponent, in application: ApplicationCandidate) -> some View {
        Toggle(isOn: Binding(
            get: { store.selectedUninstallComponentIDs.contains(component.id) },
            set: { store.setComponentSelected(component, in: application, selected: $0) }
        )) {
            HStack(spacing: 5) {
                Text(component.kind.title).lineLimit(1)
                riskBadge(component.risk)
                Text(component.confidence.title).foregroundStyle(.secondary)
                Spacer()
                Text(size(component.byteCount)).foregroundStyle(.secondary)
            }
            .font(.system(size: 8.5, design: .rounded))
        }
        .toggleStyle(.checkbox)
        .disabled(component.kind == .application || component.risk == .protected || application.removalBlocked)
    }

    private func riskBadge(_ risk: MaintenanceRisk) -> some View {
        Text(risk.title)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(riskColor(risk))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(riskColor(risk).opacity(0.12), in: Capsule())
    }

    private func riskColor(_ risk: MaintenanceRisk) -> Color {
        switch risk {
        case .recommended: return .green
        case .review: return .orange
        case .protected: return .red
        }
    }

    private func emptyFooter(tab: Int) -> some View {
        HStack {
            Button("打开完整清理屋") { store.openFullMaintenance(tab: tab) }
            Spacer()
            Button("关闭") { store.dismissQuick() }
        }
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct MaintenanceBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
