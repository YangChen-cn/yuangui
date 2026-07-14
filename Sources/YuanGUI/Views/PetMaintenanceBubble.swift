import SwiftUI

struct PetMaintenanceBubble: View {
    @ObservedObject var store: MaintenanceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
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

            if !store.isScanning && !store.isWorking && !store.quickCompleted {
                if store.quickMode == .cleanup { cleanupResults }
                else if store.quickMode == .uninstall { uninstallResults }
            }

            if store.quickCompleted {
                Button("好呀～") { store.dismissQuick() }
                    .buttonStyle(.borderedProminent).tint(.pink)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(13)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(LinearGradient(colors: [.pink.opacity(0.12), .blue.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.72), lineWidth: 0.9))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 7)
        .overlay(alignment: .bottom) {
            MaintenanceBubbleTail().fill(.regularMaterial).frame(width: 22, height: 11).offset(y: 8)
        }
    }

    private var cleanupResults: some View {
        VStack(alignment: .leading, spacing: 7) {
            if store.cleanupCandidates.isEmpty {
                Text("没有发现需要清理的内容～").foregroundStyle(.secondary)
                closeButton
            } else {
                candidateList
                let permanent = store.selectedCleanup.filter { $0.disposition == .permanent }.count
                let recyclable = store.selectedCleanup.count - permanent
                Text("已选 \(store.selectedCleanup.count) 项 · \(size(store.selectedCleanupBytes))；\(permanent) 项永久清理，\(recyclable) 项移入废纸篓")
                    .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                HStack {
                    Button("取消", action: store.dismissQuick)
                    Spacer()
                    Button("确认清理") { Task { await store.cleanSelected() } }
                        .buttonStyle(.borderedProminent).tint(.pink)
                        .disabled(store.selectedCleanupIDs.isEmpty)
                }
            }
        }
    }

    private var candidateList: some View {
        ScrollView {
            VStack(spacing: 5) {
                ForEach(Array(store.cleanupCandidates.prefix(5))) { item in
                    Toggle(isOn: Binding(
                        get: { store.selectedCleanupIDs.contains(item.id) },
                        set: { value in
                            if value { store.selectedCleanupIDs.insert(item.id) }
                            else { store.selectedCleanupIDs.remove(item.id) }
                        }
                    )) {
                        HStack {
                            Text(item.displayName).lineLimit(1)
                            Spacer()
                            Text(size(item.byteCount)).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
        .frame(maxHeight: 92)
    }

    private var uninstallResults: some View {
        VStack(alignment: .leading, spacing: 7) {
            if store.applications.isEmpty {
                Text("没有发现可列出的第三方软件～").foregroundStyle(.secondary)
                closeButton
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(Array(store.visibleApplications.prefix(5))) { app in
                            Toggle(isOn: Binding(
                                get: { store.selectedApplicationIDs.contains(app.id) },
                                set: { store.setApplicationSelected(app, selected: $0) }
                            )) {
                                HStack {
                                    Text(app.name).lineLimit(1)
                                    if app.removalBlocked {
                                        Image(systemName: "lock.fill").foregroundStyle(.orange)
                                    }
                                    Spacer()
                                    Text(size(app.reclaimableByteCount)).foregroundStyle(.secondary)
                                }
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            }
                            .toggleStyle(.checkbox)
                            .disabled(app.removalBlocked)
                        }
                    }
                }
                .frame(maxHeight: 92)
                Text("已选约 \(size(store.selectedUninstallBytes))；应用和所选用户数据会移入废纸篓，可恢复。")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                HStack {
                    Button("取消", action: store.dismissQuick)
                    Spacer()
                    Button("确认移入废纸篓") { Task { await store.uninstallSelected() } }
                        .buttonStyle(.borderedProminent).tint(.pink)
                        .disabled(store.selectedApplicationIDs.isEmpty)
                }
            }
        }
    }

    private var closeButton: some View {
        Button("关闭") { store.dismissQuick() }
            .frame(maxWidth: .infinity, alignment: .trailing)
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
