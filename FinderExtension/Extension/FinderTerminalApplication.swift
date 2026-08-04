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
}

enum FinderTerminalApplication {
    static func installedApplications() -> [FinderExternalApplication] {
        FinderExternalApplication.installedApplications(candidates: supportedCandidates)
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
    static func installedApplications() -> [FinderExternalApplication] {
        FinderExternalApplication.installedApplications(candidates: supportedCandidates)
    }

    private static let supportedCandidates: [(displayName: String, bundleIdentifier: String)] = [
        ("Visual Studio Code", "com.microsoft.VSCode"),
        ("Zed", "dev.zed.Zed"),
        ("Xcode", "com.apple.dt.Xcode"),
        ("CLion", "com.jetbrains.CLion"),
        ("Nova", "com.panic.Nova"),
        ("BBEdit", "com.barebones.bbedit"),
        ("TextEdit", "com.apple.TextEdit"),
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
