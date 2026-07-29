import SwiftUI

/// A deliberately compact companion surface. The full Cleanup House owns
/// searching and sorting; this card exposes a bounded, scrollable result list
/// and one clear primary action.
struct PetMaintenanceBubble: View {
    @ObservedObject var store: MaintenanceStore
    var placement: PetAuxiliaryBubblePlacement = .abovePet
    @Environment(\.appActions) private var appActions
    @State private var expandedApplicationID: UUID?

    private let bubbleWidth: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if let progress = store.scanProgress, progress.total > 0 {
                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    .tint(.accentColor)
                    .controlSize(.small)
            }

            if !store.isScanning && !store.isWorking && !store.quickCompleted {
                if store.quickMode == .cleanup {
                    cleanupResults
                } else if store.quickMode == .uninstall {
                    uninstallResults
                }
            }

            if store.quickCompleted {
                completionFooter
            }
        }
        .padding(12)
        .frame(width: bubbleWidth)
        .yuanPetBubbleGlass(
            .regular,
            cornerRadius: 18,
            placement: placement,
            tailWidth: 24,
            tailHeight: 12,
            tailOffset: 8
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalizer.string("清理屋"))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: store.quickMode == .cleanup ? "sparkles" : "shippingbox.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(store.quickMode == .cleanup ? .pink : .blue)
                .frame(width: 24, height: 24)

            Text(AppLocalizer.string(store.message))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            Spacer(minLength: 4)

            if store.isScanning || store.isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            Button { store.dismissQuick() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(AppLocalizer.string("取消"))
        }
    }

    private var cleanupResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.cleanupCandidates.isEmpty {
                emptyState(
                    title: "maintenance.quick.emptyCleanup",
                    tab: 0
                )
            } else {
                Text(
                    AppLocalizer.format(
                        "maintenance.quick.cleanupSummary",
                        store.cleanupCandidates.count,
                        size(store.cleanupCandidates.reduce(0) { $0 + $1.byteCount })
                    )
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(store.cleanupCandidates) { candidate in
                            cleanupCandidateRow(candidate)
                        }
                    }
                }
                .frame(maxHeight: 142)

                actionBar(tab: 0)
            }
        }
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
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.displayName)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(candidate.category.title)
                        .font(.system(size: 8.5, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)

                Spacer(minLength: 5)

                Text(size(candidate.byteCount))
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(candidate.risk == .protected)
        .padding(.vertical, 2)
    }

    private var uninstallResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.applications.isEmpty {
                emptyState(
                    title: "maintenance.quick.emptyUninstall",
                    tab: 1
                )
            } else {
                Text(
                    AppLocalizer.format(
                        "maintenance.quick.uninstallSummary",
                        store.selectedApplications.count,
                        size(store.selectedUninstallBytes)
                    )
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(store.visibleApplications) { application in
                            applicationCard(application)
                        }
                    }
                }
                .frame(maxHeight: 150)

                actionBar(tab: 1)
            }
        }
    }

    private func applicationCard(_ application: ApplicationCandidate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Toggle("", isOn: Binding(
                    get: { store.selectedApplicationIDs.contains(application.id) },
                    set: { store.setApplicationSelected(application, selected: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(application.removalBlocked)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(application.name)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if application.removalBlocked {
                            riskBadge(.protected)
                        } else if application.components.contains(where: { $0.risk == .review }) {
                            riskBadge(.review)
                        }
                    }
                    Text(
                        AppLocalizer.format(
                            "maintenance.quick.components",
                            application.components.count
                        )
                    )
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .layoutPriority(1)

                Spacer(minLength: 5)

                Text(size(application.reclaimableByteCount))
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !application.components.isEmpty {
                    Button {
                        expandedApplicationID = expandedApplicationID == application.id ? nil : application.id
                    } label: {
                        Image(systemName: expandedApplicationID == application.id ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(AppLocalizer.string("展开可逐组件选择"))
                }
            }

            if expandedApplicationID == application.id {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(application.components.prefix(3))) { component in
                        componentRow(component, in: application)
                    }
                }
                .padding(.leading, 22)
            }
        }
        .padding(.vertical, 3)
    }

    private func componentRow(_ component: UninstallComponent, in application: ApplicationCandidate) -> some View {
        Toggle(isOn: Binding(
            get: { store.selectedUninstallComponentIDs.contains(component.id) },
            set: { store.setComponentSelected(component, in: application, selected: $0) }
        )) {
            HStack(spacing: 5) {
                Text(component.kind.title)
                    .lineLimit(1)
                riskBadge(component.risk)
                Spacer(minLength: 3)
                Text(size(component.byteCount))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.system(size: 8.5, design: .rounded))
        }
        .toggleStyle(.checkbox)
        .disabled(component.kind == .application || component.risk == .protected || application.removalBlocked)
    }

    private func actionBar(tab: Int) -> some View {
        HStack(spacing: 6) {
            Button {
                openMaintenance(tab: tab)
            } label: {
                Label(
                    AppLocalizer.string("打开完整清理屋"),
                    systemImage: "arrow.up.right.square"
                )
            }
            .yuanSystemGlassButton()
            .controlSize(.small)

            Spacer(minLength: 0)

            Button {
                if tab == 0 {
                    Task { await store.cleanSelected() }
                } else {
                    Task { await store.uninstallSelected() }
                }
            } label: {
                Label(
                    AppLocalizer.string(
                        tab == 0
                            ? "maintenance.quick.confirmCleanup"
                            : "maintenance.quick.confirmUninstall"
                    ),
                    systemImage: tab == 0 ? "sparkles" : "trash"
                )
            }
            .yuanSystemGlassButton(isProminent: true)
            .controlSize(.small)
            .disabled(tab == 0 ? store.selectedCleanupIDs.isEmpty : store.selectedApplicationIDs.isEmpty)
        }
    }

    private func emptyState(title: String, tab: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(AppLocalizer.string(title))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button {
                    openMaintenance(tab: tab)
                } label: {
                    Label(
                        AppLocalizer.string("maintenance.quick.open"),
                        systemImage: "arrow.up.right.square"
                    )
                }
                .yuanSystemGlassButton()
                .controlSize(.small)

                Spacer(minLength: 0)

                Button(AppLocalizer.string("maintenance.quick.dismiss")) {
                    store.dismissQuick()
                }
                .yuanSystemGlassButton(isProminent: true)
                .controlSize(.small)
            }
        }
    }

    private var completionFooter: some View {
        HStack(spacing: 6) {
            Button {
                openMaintenance(tab: 2)
            } label: {
                Label(
                    AppLocalizer.string("maintenance.quick.activity"),
                    systemImage: "clock.arrow.circlepath"
                )
            }
            .yuanSystemGlassButton()
            .controlSize(.small)

            Spacer(minLength: 0)

            Button(AppLocalizer.string("maintenance.quick.dismiss")) {
                store.dismissQuick()
            }
            .yuanSystemGlassButton(isProminent: true)
            .controlSize(.small)
        }
    }

    private func riskBadge(_ risk: MaintenanceRisk) -> some View {
        Text(risk.title)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(riskColor(risk))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(riskColor(risk).opacity(0.12), in: Capsule())
    }

    private func riskColor(_ risk: MaintenanceRisk) -> Color {
        switch risk {
        case .recommended: .green
        case .review: .orange
        case .protected: .red
        }
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func openMaintenance(tab: Int) {
        store.dismissQuick()
        appActions.open(.maintenance(tab: tab))
    }
}
