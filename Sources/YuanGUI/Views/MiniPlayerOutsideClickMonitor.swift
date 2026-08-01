import AppKit
import SwiftUI

/// SwiftUI popovers attached to a nonactivating desktop panel do not always
/// receive AppKit's normal outside-click dismissal. This tiny bridge observes
/// global clicks while the mini player is open and dismisses only local clicks
/// that are outside the popover window.
struct MiniPlayerOutsideClickMonitor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.onDismiss = onDismiss
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.onDismiss = onDismiss
        context.coordinator.update(isPresented: isPresented)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.update(isPresented: false)
    }

    @MainActor
    final class Coordinator {
        weak var hostView: NSView?
        var onDismiss: () -> Void
        private var globalMonitor: Any?
        private var localMonitor: Any?
        private var isPresented = false

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func update(isPresented: Bool) {
            guard self.isPresented != isPresented else { return }
            self.isPresented = isPresented
            if isPresented {
                installMonitors()
            } else {
                removeMonitors()
            }
        }

        private func installMonitors() {
            removeMonitors()
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.dismiss()
                }
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.dismissIfOutsidePopover(event)
                }
                return event
            }
        }

        private func dismissIfOutsidePopover(_ event: NSEvent) {
            guard isPresented else { return }
            guard let eventWindow = event.window else {
                dismiss()
                return
            }
            guard let parentWindow = hostView?.window else {
                if eventWindow.level != .popUpMenu { dismiss() }
                return
            }
            if eventWindow === parentWindow {
                dismiss()
                return
            }
            if eventWindow.parent === parentWindow
                || parentWindow.childWindows?.contains(where: { $0 === eventWindow }) == true
                || eventWindow.level == .popUpMenu {
                return
            }
            dismiss()
        }

        private func dismiss() {
            guard isPresented else { return }
            isPresented = false
            removeMonitors()
            onDismiss()
        }

        private func removeMonitors() {
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            globalMonitor = nil
            localMonitor = nil
        }
    }
}
