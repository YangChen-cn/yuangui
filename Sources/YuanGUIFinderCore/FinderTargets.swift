import Foundation

public enum FinderMenuContextKind: Sendable {
    case container
    case items
}

public enum FinderTargetResolver {
    public static func creationDirectory(
        target: URL?,
        kind: FinderMenuContextKind,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let target = normalizedFileURL(target) else { return nil }
        switch kind {
        case .container:
            return isDirectory(target, fileManager: fileManager) ? target : nil
        case .items:
            return target.deletingLastPathComponent()
        }
    }

    /// The item an external application should open for the current context:
    /// the container itself on a blank-area right-click, the selected folder
    /// on a folder, and the selected file on a file.
    public static func openTarget(
        target: URL?,
        selected: [URL] = [],
        kind: FinderMenuContextKind
    ) -> URL? {
        let candidate = switch kind {
        case .container:
            target
        case .items:
            selected.first ?? target
        }
        return normalizedFileURL(candidate)
    }

    /// The directory a terminal should open for the current context. A file
    /// opens its containing directory; a folder opens itself.
    public static func openDirectory(
        target: URL?,
        selected: [URL] = [],
        kind: FinderMenuContextKind,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let candidate = openTarget(
            target: target,
            selected: selected,
            kind: kind
        ) else { return nil }
        if isDirectory(candidate, fileManager: fileManager) {
            return candidate
        }
        return candidate.deletingLastPathComponent()
    }

    public static func terminalDirectory(
        target: URL?,
        selected: [URL] = [],
        kind: FinderMenuContextKind,
        fileManager: FileManager = .default
    ) -> URL? {
        openDirectory(target: target, selected: selected, kind: kind, fileManager: fileManager)
    }

    public static func pasteDirectory(
        target: URL?,
        kind: FinderMenuContextKind,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let target = normalizedFileURL(target) else { return nil }
        switch kind {
        case .container:
            return isDirectory(target, fileManager: fileManager) ? target : nil
        case .items:
            return isDirectory(target, fileManager: fileManager) ? target : nil
        }
    }

    public static func normalizedFileURL(_ url: URL?) -> URL? {
        guard let url, url.isFileURL else { return nil }
        return url.standardizedFileURL.resolvingSymlinksInPath()
    }

    public static func isDirectory(_ url: URL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    public static func isDesktopDirectory(
        _ url: URL,
        desktopDirectories: [URL] = FileManager.default.urls(
            for: .desktopDirectory,
            in: .userDomainMask
        )
    ) -> Bool {
        guard let normalized = normalizedFileURL(url) else { return false }
        return desktopDirectories
            .compactMap(normalizedFileURL)
            .contains(normalized)
    }
}
