import Foundation

protocol MaintenanceLogging {
    func load() -> [MaintenanceOperation]
    func append(_ operation: MaintenanceOperation) throws
}

final class MaintenanceLogStore: MaintenanceLogging {
    private let fileURL: URL
    private let directoryURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        let directory = directoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YuanGUI/Maintenance", isDirectory: true)
        self.directoryURL = directory
        self.fileURL = directory.appendingPathComponent("operations.json")
        self.fileManager = fileManager
    }

    func load() -> [MaintenanceOperation] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([MaintenanceOperation].self, from: data)) ?? []
    }

    func append(_ operation: MaintenanceOperation) throws {
        var operations = load()
        operations.insert(operation, at: 0)
        operations = Array(operations.prefix(200))
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(operations)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
