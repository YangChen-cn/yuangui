import AppKit

@MainActor
protocol MiniPlayerOutsideClickMonitoring: AnyObject {
    func start(popoverWindow: NSWindow, onDismiss: @escaping () -> Void)
    func stop()
}

@MainActor
final class MiniPlayerOutsideClickEventMonitor: MiniPlayerOutsideClickMonitoring {
    nonisolated static func shouldDismiss(
        eventWindow: NSWindow?,
        popoverWindow: NSWindow
    ) -> Bool {
        eventWindow !== popoverWindow
    }

    private weak var popoverWindow: NSWindow?
    private var onDismiss: (() -> Void)?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var isMonitoring: Bool {
        globalMonitor != nil || localMonitor != nil
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    func start(popoverWindow: NSWindow, onDismiss: @escaping () -> Void) {
        stop()
        self.popoverWindow = popoverWindow
        self.onDismiss = onDismiss
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismiss()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            let eventWindow = event.window
            Task { @MainActor [weak self] in
                self?.dismissIfOutside(eventWindow: eventWindow)
            }
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        popoverWindow = nil
        onDismiss = nil
    }

    private func dismissIfOutside(eventWindow: NSWindow?) {
        guard let popoverWindow,
              Self.shouldDismiss(
                eventWindow: eventWindow,
                popoverWindow: popoverWindow
              ) else { return }
        dismiss()
    }

    private func dismiss() {
        guard let onDismiss else { return }
        stop()
        onDismiss()
    }
}
