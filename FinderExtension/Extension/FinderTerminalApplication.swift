import AppKit

/// An installed third-party application that can be offered in the Finder
/// context menu (terminals, editors, ...). Detection is purely
/// bundle-identifier based via NSWorkspace; only installed apps appear.
struct FinderExternalApplication {
    let displayName: String
    let bundleIdentifier: String
    let applicationURL: URL

    var menuImage: NSImage {
        let image = NSWorkspace.shared.icon(forFile: applicationURL.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    static func installedApplications(
        candidates: [(displayName: String, bundleIdentifier: String)],
        workspace: NSWorkspace = .shared
    ) -> [FinderExternalApplication] {
        candidates.compactMap { candidate in
            guard let url = workspace.urlForApplication(
                withBundleIdentifier: candidate.bundleIdentifier
            ) else { return nil }
            return FinderExternalApplication(
                displayName: candidate.displayName,
                bundleIdentifier: candidate.bundleIdentifier,
                applicationURL: url
            )
        }
    }

    static func cachedApplications(
        candidates: [(displayName: String, bundleIdentifier: String)],
        cacheKey: String,
        defaults: UserDefaults = .standard
    ) -> [FinderExternalApplication] {
        let paths = defaults.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
        return candidates.compactMap { candidate in
            guard let path = paths[candidate.bundleIdentifier],
                  FileManager.default.fileExists(atPath: path) else {
                return nil
            }
            return FinderExternalApplication(
                displayName: candidate.displayName,
                bundleIdentifier: candidate.bundleIdentifier,
                applicationURL: URL(fileURLWithPath: path, isDirectory: true)
            )
        }
    }

    static func refreshApplications(
        candidates: [(displayName: String, bundleIdentifier: String)],
        cacheKey: String,
        defaults: UserDefaults = .standard,
        workspace: NSWorkspace = .shared
    ) -> [FinderExternalApplication] {
        let applications = installedApplications(candidates: candidates, workspace: workspace)
        defaults.set(
            Dictionary(uniqueKeysWithValues: applications.map {
                ($0.bundleIdentifier, $0.applicationURL.path)
            }),
            forKey: cacheKey
        )
        return applications
    }
}

enum FinderTerminalApplication {
    private static let cacheKey = "finderTerminalApplications"

    static func cachedInstalledApplications() -> [FinderExternalApplication] {
        FinderExternalApplication.cachedApplications(
            candidates: supportedCandidates,
            cacheKey: cacheKey
        )
    }

    static func refreshInstalledApplications() -> [FinderExternalApplication] {
        FinderExternalApplication.refreshApplications(
            candidates: supportedCandidates,
            cacheKey: cacheKey
        )
    }

    private static let supportedCandidates: [(displayName: String, bundleIdentifier: String)] = [
        ("Kaku", "fun.tw93.kaku"),
        ("Terminal", "com.apple.Terminal"),
        ("iTerm2", "com.googlecode.iterm2"),
        ("Ghostty", "com.mitchellh.ghostty"),
        ("Warp", "dev.warp.Warp-Stable"),
        ("WezTerm", "com.github.wez.wezterm"),
        ("kitty", "net.kovidgoyal.kitty"),
        ("Alacritty", "org.alacritty"),
        ("Rio", "com.raphaelamorim.rio"),
        ("Tabby", "org.tabby"),
        ("Hyper", "co.zeit.hyper")
    ]
}

/// A small set of mainstream editors for the "open in editor" menu. Editors
/// receive the selected file or folder; only installed candidates appear.
enum FinderEditorApplication {
    private static let cacheKey = "finderEditorApplications"

    static func cachedInstalledApplications() -> [FinderExternalApplication] {
        FinderExternalApplication.cachedApplications(
            candidates: supportedCandidates,
            cacheKey: cacheKey
        )
    }

    static func refreshInstalledApplications() -> [FinderExternalApplication] {
        FinderExternalApplication.refreshApplications(
            candidates: supportedCandidates,
            cacheKey: cacheKey
        )
    }

    private static let supportedCandidates: [(displayName: String, bundleIdentifier: String)] = [
        ("Cursor", "com.todesktop.230313mzl4w4u92"),
        ("Visual Studio Code", "com.microsoft.VSCode"),
        ("Zed", "dev.zed.Zed"),
        ("Xcode", "com.apple.dt.Xcode"),
        ("CLion", "com.jetbrains.CLion"),
        ("Nova", "com.panic.Nova"),
        ("BBEdit", "com.barebones.bbedit"),
        ("Sublime Text", "com.sublimetext.4")
    ]
}

/// One submenu entry's payload: which file-system target to open and with
/// which app. Shared by the terminal and editor menus.
struct FinderApplicationMenuSelection {
    let targetURL: URL
    let applicationURL: URL
    let applicationBundleIdentifier: String

    init(targetURL: URL, applicationURL: URL, applicationBundleIdentifier: String) {
        self.targetURL = targetURL
        self.applicationURL = applicationURL
        self.applicationBundleIdentifier = applicationBundleIdentifier
    }
}
