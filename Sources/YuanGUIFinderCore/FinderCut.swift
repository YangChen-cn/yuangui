import Foundation

public struct FinderFileIdentity: Codable, Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64

    public init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }

    public static func read(
        from url: URL,
        fileManager: FileManager = .default
    ) throws -> FinderFileIdentity {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else {
            throw FinderCutError.identityUnavailable
        }
        return FinderFileIdentity(device: device, inode: inode)
    }
}

public struct FinderCutItem: Codable, Equatable, Sendable {
    public let path: String
    public let identity: FinderFileIdentity

    public init(path: String, identity: FinderFileIdentity) {
        self.path = path
        self.identity = identity
    }

    public var url: URL { URL(fileURLWithPath: path) }

    public static func capture(
        _ url: URL,
        fileManager: FileManager = .default
    ) throws -> FinderCutItem {
        guard let normalized = FinderTargetResolver.normalizedFileURL(url) else {
            throw FinderCutError.invalidSource
        }
        return try FinderCutItem(
            path: normalized.path,
            identity: FinderFileIdentity.read(from: normalized, fileManager: fileManager)
        )
    }
}

public struct FinderCutPayload: Codable, Equatable, Sendable {
    public let token: UUID
    public let items: [FinderCutItem]

    public init(token: UUID = UUID(), items: [FinderCutItem]) {
        self.token = token
        self.items = items
    }
}

public struct FinderMoveFailure: Equatable, Sendable {
    public let item: FinderCutItem
    public let reason: FinderCutError

    public init(item: FinderCutItem, reason: FinderCutError) {
        self.item = item
        self.reason = reason
    }
}

public struct FinderMoveResult: Equatable, Sendable {
    public let movedURLs: [URL]
    public let failures: [FinderMoveFailure]

    public init(movedURLs: [URL], failures: [FinderMoveFailure]) {
        self.movedURLs = movedURLs
        self.failures = failures
    }

    public var remainingItems: [FinderCutItem] { failures.map(\.item) }
}

public enum FinderCutError: String, Error, Codable, Equatable, Sendable {
    case invalidSource
    case invalidDestination
    case identityUnavailable
    case sourceChanged
    case destinationExists
    case sameDirectory
    case destinationInsideSource
    case moveFailed
}

public enum FinderMoveService {
    public static func move(
        _ payload: FinderCutPayload,
        to destinationDirectory: URL,
        fileManager: FileManager = .default
    ) -> FinderMoveResult {
        let destinationDirectory = destinationDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard FinderTargetResolver.isDirectory(destinationDirectory, fileManager: fileManager),
              fileManager.isWritableFile(atPath: destinationDirectory.path) else {
            return FinderMoveResult(
                movedURLs: [],
                failures: payload.items.map { FinderMoveFailure(item: $0, reason: .invalidDestination) }
            )
        }

        var movedURLs: [URL] = []
        var failures: [FinderMoveFailure] = []
        for item in payload.items {
            let source = item.url.standardizedFileURL.resolvingSymlinksInPath()
            guard fileManager.fileExists(atPath: source.path) else {
                failures.append(FinderMoveFailure(item: item, reason: .sourceChanged))
                continue
            }
            guard (try? FinderFileIdentity.read(from: source, fileManager: fileManager)) == item.identity else {
                failures.append(FinderMoveFailure(item: item, reason: .sourceChanged))
                continue
            }
            if source.deletingLastPathComponent() == destinationDirectory {
                failures.append(FinderMoveFailure(item: item, reason: .sameDirectory))
                continue
            }
            if FinderTargetResolver.isDirectory(source, fileManager: fileManager),
               isDescendant(destinationDirectory, of: source) {
                failures.append(FinderMoveFailure(item: item, reason: .destinationInsideSource))
                continue
            }

            let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
            guard !fileManager.fileExists(atPath: destination.path) else {
                failures.append(FinderMoveFailure(item: item, reason: .destinationExists))
                continue
            }
            do {
                try fileManager.moveItem(at: source, to: destination)
                movedURLs.append(destination)
            } catch {
                failures.append(FinderMoveFailure(item: item, reason: .moveFailed))
            }
        }
        return FinderMoveResult(movedURLs: movedURLs, failures: failures)
    }

    private static func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let directoryPath = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        return candidate.path.hasPrefix(directoryPath)
    }
}
