import AppKit
import FinderSync

@MainActor
final class FinderExtensionController: ObservableObject {
    private static let extensionBundleIdentifier = "com.yang.yuangui.FinderExtension"

    @Published private(set) var isEnabled = false
    @Published private(set) var isBundled = false

    private var activationObserver: NSObjectProtocol?

    func start() {
        refresh()
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func stop() {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    func refresh() {
        if let pluginsURL = Bundle.main.builtInPlugInsURL {
            let extensionURL = pluginsURL.appendingPathComponent(
                "YuanGUIFinderExtension.appex",
                isDirectory: true
            )
            isBundled = FileManager.default.fileExists(atPath: extensionURL.path)
        } else {
            isBundled = false
        }

        // FinderSync's host query can report false for locally signed development
        // copies even while PluginKit has elected and launched the extension. A running
        // extension process is direct public-API evidence that it is usable.
        let isExtensionRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.extensionBundleIdentifier
        ).isEmpty
        isEnabled = isBundled && (FIFinderSyncController.isExtensionEnabled || isExtensionRunning)
    }

    func openManagement() {
        FIFinderSyncController.showExtensionManagementInterface()
    }
}
