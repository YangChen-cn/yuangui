import AppKit
import OSLog

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
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yang.yuangui",
        category: "WindowActivation"
    )

    nonisolated static func canPresentWindow(isApplicationActive: Bool) -> Bool {
        isApplicationActive
    }

    private weak var requestedWindow: NSWindow?
    private var shouldMakeMain = false
    private var activationObserver: NSObjectProtocol?
    private var activationRetryTask: Task<Void, Never>?
    private var presentationGeneration: UInt64 = 0
    private let notificationCenter: NotificationCenter
    private let retryDelays: [Duration]
    private let isApplicationActive: @MainActor () -> Bool
    private let activateApplication: @MainActor () -> Void

    init(
        notificationCenter: NotificationCenter = .default,
        retryDelays: [Duration] = [.milliseconds(80), .milliseconds(180), .milliseconds(360)],
        isApplicationActive: @escaping @MainActor () -> Bool = { NSApp.isActive },
        activateApplication: @escaping @MainActor () -> Void = {
            NSApp.activate()
        }
    ) {
        self.notificationCenter = notificationCenter
        self.retryDelays = retryDelays
        self.isApplicationActive = isApplicationActive
        self.activateApplication = activateApplication
        activationObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Self.logger.info("Application became active; checking pending window")
                self?.presentPendingWindowIfPossible()
            }
        }
    }

    deinit {
        activationRetryTask?.cancel()
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
        }
    }

    func present(_ window: NSWindow, makeMain: Bool) {
        presentationGeneration &+= 1
        activationRetryTask?.cancel()
        requestedWindow = window
        shouldMakeMain = makeMain
        Self.logger.info(
            "Window presentation requested; active=\(self.isApplicationActive(), privacy: .public), visible=\(window.isVisible, privacy: .public), makeMain=\(makeMain, privacy: .public)"
        )
        window.orderFrontRegardless()
        Self.logger.info(
            "Window ordered front before activation; visible=\(window.isVisible, privacy: .public)"
        )
        activateApplication()
        presentPendingWindowIfPossible()
        scheduleActivationRetriesIfNeeded(generation: presentationGeneration)
    }

    private func presentPendingWindowIfPossible() {
        guard Self.canPresentWindow(isApplicationActive: isApplicationActive()),
              let window = requestedWindow else { return }

        requestedWindow = nil
        activationRetryTask?.cancel()
        activationRetryTask = nil
        let makeMain = shouldMakeMain
        shouldMakeMain = false
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        if makeMain {
            window.makeMain()
        }
        Self.logger.info(
            "Window presented; visible=\(window.isVisible, privacy: .public), key=\(window.isKeyWindow, privacy: .public), main=\(window.isMainWindow, privacy: .public)"
        )
    }

    private func scheduleActivationRetriesIfNeeded(generation: UInt64) {
        guard requestedWindow != nil, !retryDelays.isEmpty else { return }
        activationRetryTask = Task { [weak self] in
            guard let self else { return }
            for (index, delay) in retryDelays.enumerated() {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      generation == presentationGeneration,
                      requestedWindow != nil else { return }
                Self.logger.info(
                    "Retrying application activation; attempt=\(index + 1, privacy: .public)"
                )
                activateApplication()
                await Task.yield()
                presentPendingWindowIfPossible()
            }
            if generation == presentationGeneration, requestedWindow != nil {
                Self.logger.error("Window remains pending after bounded activation retries")
            }
        }
    }
}
