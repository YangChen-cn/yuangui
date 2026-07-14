import Foundation

@MainActor
final class MaintenanceStore: ObservableObject {
    @Published private(set) var cleanupCandidates: [CleanupCandidate] = []
    @Published private(set) var applications: [ApplicationCandidate] = []
    @Published private(set) var operations: [MaintenanceOperation]
    @Published var selectedCleanupIDs: Set<UUID> = []
    @Published var selectedApplicationIDs: Set<UUID> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isWorking = false
    @Published private(set) var message = "VCC 准备好扫描啦，master 随时叫我们～"
    @Published private(set) var whitelistedPaths: [String]

    private let scanner: CleanupScanning
    private let handler: MaintenanceHandling
    private let logger: MaintenanceLogging
    private let pet: PetStore
    private let defaults: UserDefaults

    init(
        pet: PetStore,
        scanner: CleanupScanning = CleanupScanner(),
        handler: MaintenanceHandling = NativeMaintenanceService(),
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
    }

    var selectedCleanup: [CleanupCandidate] { cleanupCandidates.filter { selectedCleanupIDs.contains($0.id) } }
    var selectedApplications: [ApplicationCandidate] { applications.filter { selectedApplicationIDs.contains($0.id) } }
    var selectedCleanupBytes: Int64 { selectedCleanup.reduce(0) { $0 + $1.byteCount } }

    func scanCleanup() async {
        guard !isScanning else { return }
        isScanning = true
        message = "VCC 正在认真扫描可以清理的内容…"
        pet.beginMaintenance(message: message)
        let found = await scanner.scan(excluding: Set(whitelistedPaths))
        cleanupCandidates = found
        selectedCleanupIDs = Set(found.filter { $0.category.selectedByDefault }.map(\.id))
        isScanning = false
        message = found.isEmpty
            ? "没有发现需要清理的内容，Mac 很干净～"
            : "VCC 扫描到了这些可以清理的内容，master 要看看吗？"
        pet.endMaintenance(message: message, success: false)
    }

    func scanApplications() async {
        guard !isScanning else { return }
        isScanning = true
        message = "VCC 正在清点 Mac 里的软件…"
        pet.beginMaintenance(message: message)
        applications = await scanner.scanApplications()
        selectedApplicationIDs = []
        isScanning = false
        message = "VCC 扫描到了这些软件，master 要卸载吗？"
        pet.endMaintenance(message: message, success: false)
    }

    func cleanSelected() async {
        let selected = selectedCleanup
        guard !selected.isEmpty, !isWorking else { return }
        isWorking = true
        message = "元圭和 VCC 正在一起整理，请稍等一下～"
        pet.beginMaintenance(message: message)
        let result = await handler.clean(selected)
        finish(result)
        cleanupCandidates.removeAll { selectedCleanupIDs.contains($0.id) }
        selectedCleanupIDs = []
    }

    func uninstallSelected() async {
        let selected = selectedApplications
        guard !selected.isEmpty, !isWorking else { return }
        isWorking = true
        message = "VCC 正在把选中的软件送进废纸篓…"
        pet.beginMaintenance(message: message)
        let result = await handler.uninstall(selected)
        finish(result)
        applications.removeAll { selectedApplicationIDs.contains($0.id) }
        selectedApplicationIDs = []
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

    func openTrash() { pet.openTrash() }

    func refreshOperations() { operations = logger.load() }

    private func finish(_ result: MaintenanceOperation) {
        isWorking = false
        operations = logger.load()
        let size = ByteCountFormatter.string(fromByteCount: result.reclaimedBytes, countStyle: .file)
        if result.itemCount > 0 {
            message = "元圭和 VCC 帮 master 清出了 \(size)，Mac 轻松多啦～"
            pet.endMaintenance(message: message, success: true)
        } else if let error = result.errors.first {
            message = "这次没有清理成功：\(error)"
            pet.endMaintenance(message: message, success: false)
        } else {
            message = "没有需要处理的项目～"
            pet.endMaintenance(message: message, success: false)
        }
    }
}
