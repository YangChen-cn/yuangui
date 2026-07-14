import Foundation

enum BundleIdentifierValidator {
    static func isValid(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy {
                $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
            }
        }
    }
}

enum SafePathError: LocalizedError, Equatable {
    case empty
    case relative
    case traversal
    case controlCharacter
    case symbolicLink
    case protectedPath(String)
    case outsideAllowedRoots
    case rootItself

    var errorDescription: String? {
        switch self {
        case .empty: return "路径为空"
        case .relative: return "只允许绝对路径"
        case .traversal: return "路径包含不安全的上级跳转"
        case .controlCharacter: return "路径包含控制字符"
        case .symbolicLink: return "拒绝处理符号链接"
        case .protectedPath(let name): return "受保护内容：\(name)"
        case .outsideAllowedRoots: return "路径不在允许清理的目录中"
        case .rootItself: return "不能清理目录根本身"
        }
    }
}

struct SafePathValidator {
    let allowedRoots: [URL]
    private let protectedFragments = [
        "Keychains", "/Messages", "/Notes", "Mobile Documents", "Group Containers",
        "CloudStorage", "com.yang.yuangui", "/YuanGUI/", "Safari/History", "Cookies"
    ]

    init(allowedRoots: [URL] = SafePathValidator.defaultAllowedRoots) {
        self.allowedRoots = allowedRoots.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
    }

    func validate(_ url: URL) throws -> URL {
        let raw = url.path
        guard !raw.isEmpty else { throw SafePathError.empty }
        guard raw.hasPrefix("/") else { throw SafePathError.relative }
        guard !raw.split(separator: "/", omittingEmptySubsequences: false).contains("..") else { throw SafePathError.traversal }
        guard raw.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { throw SafePathError.controlCharacter }
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values?.isSymbolicLink != true else { throw SafePathError.symbolicLink }
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        if let fragment = protectedFragments.first(where: { resolved.path.localizedCaseInsensitiveContains($0) }) {
            throw SafePathError.protectedPath(fragment)
        }
        for root in allowedRoots {
            if resolved.path == root.path { throw SafePathError.rootItself }
            if resolved.path.hasPrefix(root.path + "/") { return resolved }
        }
        throw SafePathError.outsideAllowedRoots
    }

    static var defaultAllowedRoots: [URL] {
        let fm = FileManager.default
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return [
            library.appendingPathComponent("Caches"),
            library.appendingPathComponent("Logs"),
            library.appendingPathComponent("Application Support"),
            library.appendingPathComponent("Preferences"),
            library.appendingPathComponent("Saved Application State"),
            library.appendingPathComponent("WebKit"),
            library.appendingPathComponent("HTTPStorages"),
            library.appendingPathComponent("Containers"),
            library.appendingPathComponent("Application Scripts"),
            library.appendingPathComponent("LaunchAgents"),
            library.appendingPathComponent("Developer/Xcode/DerivedData"),
            fm.temporaryDirectory
        ]
    }
}
