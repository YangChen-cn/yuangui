import AppKit

@MainActor
protocol ApplicationWindowActivating: AnyObject {
    func present(_ window: NSWindow, makeMain: Bool)
}

extension ApplicationWindowActivating {
    func present(_ window: NSWindow) {
        present(window, makeMain: false)
    }
}

/// Activates the accessory application before making one of its regular
/// windows key. In particular, this avoids competing with a popover that is
/// still restoring the responder chain while it closes.
@MainActor
final class ApplicationWindowActivator: ApplicationWindowActivating {
    nonisolated static func canPresentWindow(isApplicationActive: Bool) -> Bool {
        isApplicationActive
    }

    private weak var requestedWindow: NSWindow?
    private var shouldMakeMain = false
    private var activationObserver: NSObjectProtocol?
    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        activationObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.presentPendingWindowIfPossible()
            }
        }
    }

    deinit {
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
        }
    }

    func present(_ window: NSWindow, makeMain: Bool) {
        requestedWindow = window
        shouldMakeMain = makeMain
        NSApp.activate(ignoringOtherApps: true)
        presentPendingWindowIfPossible()
    }

    private func presentPendingWindowIfPossible() {
        guard Self.canPresentWindow(isApplicationActive: NSApp.isActive),
              let window = requestedWindow else { return }

        requestedWindow = nil
        let makeMain = shouldMakeMain
        shouldMakeMain = false
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        if makeMain {
            window.makeMain()
        }
    }
}
