import AppKit
import Foundation

@MainActor
protocol TrashHandling: AnyObject {
    func recycle(_ urls: [URL]) async throws -> Int
    func openTrash()
    func emptyTrash() throws
}

enum TrashServiceError: LocalizedError {
    case appleScript([String: Any])

    var errorDescription: String? {
        switch self {
        case .appleScript(let details):
            return details[NSAppleScript.errorMessage] as? String ?? "Finder 无法清空废纸篓"
        }
    }
}

@MainActor
final class TrashService: TrashHandling {
    func recycle(_ urls: [URL]) async throws -> Int {
        let uniqueURLs = Array(Set(urls.filter { $0.isFileURL })).filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard !uniqueURLs.isEmpty else { return 0 }

        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.recycle(uniqueURLs) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: uniqueURLs.count)
                }
            }
        }
    }

    func openTrash() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        NSWorkspace.shared.open(url)
    }

    func emptyTrash() throws {
        let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error = error as? [String: Any] {
            throw TrashServiceError.appleScript(error)
        }
    }
}
