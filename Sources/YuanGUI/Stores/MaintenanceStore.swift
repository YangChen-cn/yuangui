import Foundation

@MainActor
final class MaintenanceStore: ObservableObject {
    enum QuickMode: Equatable { case cleanup, uninstall }
    enum SortOrder: String, CaseIterable, Identifiable {
        case size
        case name
        case lastUsed

        var id: String { rawValue }
        var title: String {
            switch self {
            case .size: return AppLocalizer.string("按大小")
            case .name: return AppLocalizer.string("按名称")
            case .lastUsed: return AppLocalizer.string("按最近使用")
            }
        }
    }

    @Published private(set) var cleanupCandidates: [CleanupCandidate] = []
    @Published private(set) var applications: [ApplicationCandidate] = []
    @Published private(set) var operations: [MaintenanceOperation]
    @Published var selectedCleanupIDs: Set<UUID> = []
    @Published var selectedApplicationIDs: Set<UUID> = []
    @Published var selectedUninstallComponentIDs: Set<UUID> = []
    @Published var searchText = ""
    @Published var sortOrder: SortOrder = .size
    @Published private(set) var isScanning = false
    @Published private(set) var isWorking = false
    @Published private(set) var message = AppLocalizer.string("maintenance.status.ready")
    @Published private(set) var whitelistedPaths: [String]
    @Published private(set) var projectScanRoots: [String]
    @Published private(set) var enabledCleanupCategories: Set<CleanupCategory>
    @Published var selectedTab = 0
    @Published private(set) var quickMode: QuickMode?
    @Published private(set) var quickCompleted = false
    @Published private(set) var scanProgress: MaintenanceScanProgress?

    /// An injected scanner is retained for tests. The production scanner is deliberately
    /// created only when the user starts a cleanup scan, so presenting the companion
    /// never touches protected folders such as Desktop or Downloads.
    private let scanner: CleanupScanning?
    /// Like scanning, destructive-operation support is created only after the user
    /// confirms an operation. Its path validator must not inspect protected folders
    /// while the companion is merely being presented.
    private let handler: MaintenanceHandling?
    private let logger: MaintenanceLogging
    private let pet: PetStore
    private let defaults: UserDefaults

    init(
        pet: PetStore,
        scanner: CleanupScanning? = nil,
        handler: MaintenanceHandling? = nil,
        logger: MaintenanceLogging = MaintenanceLogStore(),
        defaults: UserDefaults = .standard
    ) {
        self.pet = pet
        self.scanner = scanner
        self.handler = handler
        self.logger = logger
        self.defaults = defaults
        self.operations = logger.load()
        self.whitelistedPaths = defaults.stringArray(forKey: "maintenanceWhitelist") ?? []
        self.projectScanRoots = defaults.stringArray(forKey: "maintenanceProjectRoots")
            ?? CleanupScanConfiguration.defaults().projectRoots
        let storedCategories = defaults.stringArray(forKey: "maintenanceEnabledCategories")
            ?? CleanupScanConfiguration.defaultEnabledCategories.map(\.rawValue)
        self.enabledCleanupCategories = Set(storedCategories.compactMap(CleanupCategory.init(rawValue:)))
    }

    var selectedCleanup: [CleanupCandidate] { cleanupCandidates.filter { selectedCleanupIDs.contains($0.id) } }
    var selectedApplications: [ApplicationCandidate] {
        applications
            .filter { selectedApplicationIDs.contains($0.id) }
            .map { $0.selectingComponents(selectedUninstallComponentIDs) }
    }
    var selectedCleanupBytes: Int64 { selectedCleanup.reduce(0) { $0 + $1.byteCount } }
    var selectedUninstallBytes: Int64 {
        selectedApplications.reduce(0) { $0 + $1.reclaimableByteCount }
    }

    var visibleCleanupCandidates: [CleanupCandidate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let values = cleanupCandidates.filter {
            query.isEmpty || $0.displayName.lowercased().contains(query) || $0.url.path.lowercased().contains(query)
        }
        switch sortOrder {
        case .size: return values.sorted { $0.byteCount > $1.byteCount }
        case .name: return values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .lastUsed: return values.sorted { ($0.modifiedAt ?? .distantPast) < ($1.modifiedAt ?? .distantPast) }
        }
    }

    var visibleApplications: [ApplicationCandidate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let values = applications.filter {
            query.isEmpty || $0.name.lowercased().contains(query) || $0.bundleIdentifier.lowercased().contains(query)
        }
        switch sortOrder {
        case .size: return values.sorted { $0.reclaimableByteCount > $1.reclaimableByteCount }
        case .name: return values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastUsed: return values.sorted { ($0.lastUsedAt ?? .distantPast) < ($1.lastUsedAt ?? .distantPast) }
        }
    }

    func startQuickCleanup() async {
        quickMode = .cleanup
        quickCompleted = false
        await scanCleanup()
    }

    func startQuickUninstall() async {
        quickMode = .uninstall
        quickCompleted = false
        await scanApplications()
    }

    func dismissQuick() {
        quickMode = nil
        quickCompleted = false
    }

    func scanCleanup() async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = nil
        message = AppLocalizer.string("maintenance.status.scanningCleanup")
        pet.beginMaintenance(message: message)
        let scanner = scanner ?? CleanupScanner()
        let found = await scanner.scan(configuration: scanConfiguration) { [weak self] progress in
            Task { @MainActor in
                self?.scanProgress = progress
                self?.message = progress.message
            }
        }
        guard !Task.isCancelled else {
            isScanning = false
            scanProgress = nil
            message = AppLocalizer.string("maintenance.status.cleanupScanCancelled")
            pet.endMaintenance(message: message, success: false)
            return
        }
        cleanupCandidates = found
        selectedCleanupIDs = Set(found.filter { $0.selectedByDefault && $0.risk == .recommended }.map(\.id))
        isScanning = false
        scanProgress = nil
        message = found.isEmpty
            ? AppLocalizer.string("maintenance.status.nothingToClean")
            : AppLocalizer.string("maintenance.status.cleanupScanComplete")
        pet.endMaintenance(message: message, success: false)
    }

    func scanApplications() async {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = nil
        message = AppLocalizer.string("maintenance.status.scanningApps")
        pet.beginMaintenance(message: message)
        let scanner = scanner ?? CleanupScanner()
        applications = await scanner.scanApplications { [weak self] progress in
            Task { @MainActor in
                self?.scanProgress = progress
                self?.message = progress.message
            }
        }
        guard !Task.isCancelled else {
            isScanning = false
            scanProgress = nil
            message = AppLocalizer.string("maintenance.status.appScanCancelled")
            pet.endMaintenance(message: message, success: false)
            return
        }
        selectedApplicationIDs = []
        selectedUninstallComponentIDs = []
        isScanning = false
        scanProgress = nil
        message = AppLocalizer.string("maintenance.status.appScanComplete")
        pet.endMaintenance(message: message, success: false)
    }

    func cleanSelected() async {
        // The mini companion card is intentionally limited to low-risk
        // recommendations. Review items must be handled from the full
        // Cleanup House, where the explicit confirmation flow is available;
        // protected items are never executable from either surface.
        let selected = selectedCleanup.filter {
            $0.risk != .protected
                && (quickMode != .cleanup || $0.risk == .recommended)
        }
        guard !selected.isEmpty, !isWorking else { return }
        isWorking = true
        message = AppLocalizer.string("maintenance.status.cleaning")
        pet.beginMaintenance(message: message)
        let handler = handler ?? NativeMaintenanceService()
        let result = await handler.clean(selected)
        finish(result)
        let completedPaths = Set((result.results ?? []).filter {
            $0.outcome == .deleted || $0.outcome == .trashed
        }.map(\.path))
        cleanupCandidates.removeAll { completedPaths.contains($0.url.path) }
        selectedCleanupIDs = []
    }

    func uninstallSelected() async {
        let selected = selectedApplications.compactMap { application -> ApplicationCandidate? in
            let components = application.components.filter {
                $0.risk != .protected
                    && (quickMode != .uninstall || $0.risk == .recommended)
            }
            guard !components.isEmpty else { return nil }
            return application.selectingComponents(Set(components.map(\.id)))
        }
        guard !selected.isEmpty, !isWorking else { return }
        isWorking = true
        message = AppLocalizer.string("maintenance.status.uninstalling")
        pet.beginMaintenance(message: message)
        let handler = handler ?? NativeMaintenanceService()
        let result = await handler.uninstall(selected)
        finish(result)
        let completedPaths = Set((result.results ?? []).filter { $0.outcome == .trashed }.map(\.path))
        applications.removeAll { completedPaths.contains($0.url.path) }
        selectedApplicationIDs = []
        selectedUninstallComponentIDs = []
    }

    func addToWhitelist(_ candidate: CleanupCandidate) {
        var values = Set(whitelistedPaths)
        values.insert(candidate.url.path)
        whitelistedPaths = Array(values).sorted()
        defaults.set(whitelistedPaths, forKey: "maintenanceWhitelist")
        cleanupCandidates.removeAll { $0.id == candidate.id }
        selectedCleanupIDs.remove(candidate.id)
    }

    func removeFromWhitelist(_ path: String) {
        whitelistedPaths.removeAll { $0 == path }
        defaults.set(whitelistedPaths, forKey: "maintenanceWhitelist")
    }

    func clearWhitelist() {
        whitelistedPaths = []
        defaults.removeObject(forKey: "maintenanceWhitelist")
    }

    func addProjectScanRoot(_ url: URL) {
        let root = url.standardizedFileURL.resolvingSymlinksInPath()
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        guard root.path != home.path,
              root.path.hasPrefix(home.path + "/"),
              !projectScanRoots.contains(root.path) else { return }
        projectScanRoots.append(root.path)
        projectScanRoots.sort()
        defaults.set(projectScanRoots, forKey: "maintenanceProjectRoots")
    }

    func removeProjectScanRoot(_ path: String) {
        projectScanRoots.removeAll { $0 == path }
        defaults.set(projectScanRoots, forKey: "maintenanceProjectRoots")
    }

    func setCategory(_ category: CleanupCategory, enabled: Bool) {
        if enabled { enabledCleanupCategories.insert(category) }
        else { enabledCleanupCategories.remove(category) }
        defaults.set(enabledCleanupCategories.map(\.rawValue).sorted(), forKey: "maintenanceEnabledCategories")
    }

    func openTrash() { pet.openTrash() }

    func selectRecommendedCleanup() {
        selectedCleanupIDs = Set(cleanupCandidates.filter {
            $0.risk == .recommended && $0.selectedByDefault
        }.map(\.id))
    }

    func setCleanupSelected(_ candidate: CleanupCandidate, selected: Bool) {
        guard candidate.risk != .protected,
              (quickMode != .cleanup || candidate.risk == .recommended) else { return }
        if selected { selectedCleanupIDs.insert(candidate.id) }
        else { selectedCleanupIDs.remove(candidate.id) }
    }

    func setApplicationSelected(_ application: ApplicationCandidate, selected: Bool) {
        if selected {
            guard !application.removalBlocked else { return }
            selectedApplicationIDs.insert(application.id)
            selectedUninstallComponentIDs.formUnion(application.components.filter {
                $0.selectedByDefault
                    && $0.risk != .protected
                    && (quickMode != .uninstall || $0.risk == .recommended)
            }.map(\.id))
        } else {
            selectedApplicationIDs.remove(application.id)
            selectedUninstallComponentIDs.subtract(application.components.map(\.id))
        }
    }

    func setComponentSelected(_ component: UninstallComponent, in application: ApplicationCandidate, selected: Bool) {
        guard component.risk != .protected,
              (quickMode != .uninstall || component.risk == .recommended),
              !application.removalBlocked else { return }
        if selected {
            selectedApplicationIDs.insert(application.id)
            selectedUninstallComponentIDs.insert(component.id)
            if let appBody = application.components.first(where: { $0.kind == .application }) {
                selectedUninstallComponentIDs.insert(appBody.id)
            }
        } else if component.kind != .application {
            selectedUninstallComponentIDs.remove(component.id)
        }
    }

    func selectTab(_ tab: Int) { selectedTab = min(max(tab, 0), 2) }

    func refreshOperations() { operations = logger.load() }

    var scanConfiguration: CleanupScanConfiguration {
        CleanupScanConfiguration(
            projectRoots: projectScanRoots,
            whitelistedPaths: whitelistedPaths,
            enabledCategories: enabledCleanupCategories
        )
    }

    private func finish(_ result: MaintenanceOperation) {
        isWorking = false
        quickCompleted = quickMode != nil
        operations = logger.load()
        let permanent = ByteCountFormatter.string(
            fromByteCount: result.permanentlyDeletedBytes ?? 0,
            countStyle: .file
        )
        let trashed = ByteCountFormatter.string(
            fromByteCount: result.trashedBytes ?? 0,
            countStyle: .file
        )
        if result.itemCount > 0 {
            if (result.permanentlyDeletedBytes ?? 0) > 0, (result.trashedBytes ?? 0) > 0 {
                message = AppLocalizer.format("maintenance.result.deletedAndTrashed", permanent, trashed)
            } else if (result.permanentlyDeletedBytes ?? 0) > 0 {
                message = AppLocalizer.format("maintenance.result.deleted", permanent)
            } else {
                message = AppLocalizer.format("maintenance.result.trashed", trashed)
            }
            pet.endMaintenance(message: message, success: true)
        } else if let error = result.errors.first {
            message = AppLocalizer.format("maintenance.result.failed", error)
            pet.endMaintenance(message: message, success: false)
        } else {
            message = AppLocalizer.string("maintenance.result.noItems")
            pet.endMaintenance(message: message, success: false)
        }
    }
}
