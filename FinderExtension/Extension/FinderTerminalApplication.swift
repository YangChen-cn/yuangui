import AppKit

struct FinderTerminalApplication {
    let displayName: String
    let bundleIdentifier: String
    let applicationURL: URL

    var menuImage: NSImage {
        let image = NSWorkspace.shared.icon(forFile: applicationURL.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    static func installedApplications(
        workspace: NSWorkspace = .shared
    ) -> [FinderTerminalApplication] {
        supportedApplications.compactMap { candidate in
            guard let url = workspace.urlForApplication(
                withBundleIdentifier: candidate.bundleIdentifier
            ) else { return nil }
            return FinderTerminalApplication(
                displayName: candidate.displayName,
                bundleIdentifier: candidate.bundleIdentifier,
                applicationURL: url
            )
        }
    }

    private static let supportedApplications: [(displayName: String, bundleIdentifier: String)] = [
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

struct FinderTerminalMenuSelection {
    let directoryURL: URL
    let applicationURL: URL
    let applicationBundleIdentifier: String

    init(directoryURL: URL, applicationURL: URL, applicationBundleIdentifier: String) {
        self.directoryURL = directoryURL
        self.applicationURL = applicationURL
        self.applicationBundleIdentifier = applicationBundleIdentifier
    }
}
