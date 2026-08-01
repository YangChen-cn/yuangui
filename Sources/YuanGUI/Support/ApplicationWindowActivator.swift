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

@MainActor
final class ApplicationWindowActivator: ApplicationWindowActivating {
    nonisolated static func shouldFinishActivation(
        isApplicationActive: Bool,
        isWindowVisible: Bool,
        isWindowKey: Bool,
        requiresMainWindow: Bool,
        isWindowMain: Bool
    ) -> Bool {
        isApplicationActive
            && isWindowVisible
            && isWindowKey
            && (!requiresMainWindow || isWindowMain)
    }

    nonisolated static func shouldRecoverActivationForKeyWindow(
        isApplicationActive: Bool,
        isWindowVisible: Bool,
        isNonactivatingPanel: Bool
    ) -> Bool {
        !isApplicationActive && isWindowVisible && !isNonactivatingPanel
    }

    nonisolated static func shouldCoordinateActivation(
        currentProcessID: pid_t,
        frontmostProcessID: pid_t?
    ) -> Bool {
        guard let frontmostProcessID else { return false }
        return frontmostProcessID != currentProcessID
    }

    private weak var requestedWindow: NSWindow?
    private var shouldMakeMain = false
    private var requestGeneration: UInt = 0
    private var expirationTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private var keyWindowObserver: NSObjectProtocol?
    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        observer = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.finishPendingActivation()
            }
        }
        keyWindowObserver = notificationCenter.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let window = notification.object as? NSWindow else { return }
                self?.recoverActivationIfNeeded(for: window)
            }
        }
    }

    deinit {
        expirationTask?.cancel()
        if let observer {
            notificationCenter.removeObserver(observer)
        }
        if let keyWindowObserver {
            notificationCenter.removeObserver(keyWindowObserver)
        }
    }

    func present(_ window: NSWindow, makeMain: Bool) {
        requestGeneration &+= 1
        let generation = requestGeneration
        requestedWindow = window
        shouldMakeMain = makeMain

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        requestApplicationActivation(coordinatingFromFrontmostApplication: true)
        finishPendingActivation()
        scheduleExpiration(for: window, generation: generation)
    }

    private func recoverActivationIfNeeded(for window: NSWindow) {
        guard requestedWindow !== window else { return }
        guard Self.shouldRecoverActivationForKeyWindow(
            isApplicationActive: NSApp.isActive,
            isWindowVisible: window.isVisible,
            isNonactivatingPanel: window.styleMask.contains(.nonactivatingPanel)
        ) else { return }

        requestGeneration &+= 1
        let generation = requestGeneration
        requestedWindow = window
        shouldMakeMain = window.canBecomeMain
        requestApplicationActivation(coordinatingFromFrontmostApplication: true)
        finishPendingActivation()
        scheduleExpiration(for: window, generation: generation)
    }

    private func scheduleExpiration(for window: NSWindow, generation: UInt) {
        guard requestedWindow != nil else { return }
        expirationTask?.cancel()
        expirationTask = Task { [weak self, weak window] in
            await Task.yield()
            guard let self, let window,
                  requestGeneration == generation,
                  requestedWindow === window else { return }
            if !NSApp.isActive {
                requestApplicationActivation(coordinatingFromFrontmostApplication: false)
            }
            finishPendingActivation()

            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled,
                  requestGeneration == generation,
                  requestedWindow === window else { return }
            clearPendingActivation()
        }
    }

    private func finishPendingActivation() {
        guard let window = requestedWindow else { return }
        guard window.isVisible else {
            clearPendingActivation()
            return
        }
        guard NSApp.isActive else { return }

        window.makeKeyAndOrderFront(nil)
        if shouldMakeMain {
            window.makeMain()
        }
        if Self.shouldFinishActivation(
            isApplicationActive: NSApp.isActive,
            isWindowVisible: window.isVisible,
            isWindowKey: window.isKeyWindow,
            requiresMainWindow: shouldMakeMain,
            isWindowMain: window.isMainWindow
        ) {
            clearPendingActivation()
        }
    }

    private func requestApplicationActivation(coordinatingFromFrontmostApplication: Bool) {
        if coordinatingFromFrontmostApplication {
            let currentApplication = NSRunningApplication.current
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
            if Self.shouldCoordinateActivation(
                currentProcessID: currentApplication.processIdentifier,
                frontmostProcessID: frontmostApplication?.processIdentifier
            ), let frontmostApplication,
               currentApplication.activate(from: frontmostApplication, options: []) {
                return
            }
        }
        NSApp.activate()
    }

    private func clearPendingActivation() {
        expirationTask?.cancel()
        expirationTask = nil
        requestedWindow = nil
        shouldMakeMain = false
    }
}
