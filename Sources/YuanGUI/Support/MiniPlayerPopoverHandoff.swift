import AppKit
import SwiftUI

struct MiniPlayerPopoverTransition {
    private(set) var isFullPlayerPending = false
    private(set) var observedWillClose = false

    mutating func requestFullPlayer() -> Bool {
        guard !isFullPlayerPending else { return false }
        isFullPlayerPending = true
        return true
    }

    mutating func popoverWillClose() {
        observedWillClose = true
    }

    mutating func popoverDidClose() -> Bool {
        defer {
            isFullPlayerPending = false
            observedWillClose = false
        }
        return isFullPlayerPending && observedWillClose
    }
}

@MainActor
final class MiniPlayerPopoverHandoff: NSObject, ObservableObject {
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private weak var probeView: NSView?
    private var popover: NSPopover?
    private weak var popoverWindow: NSWindow?
    private var transition = MiniPlayerPopoverTransition()
    private var pendingAction: (() -> Void)?

    override convenience init() {
        self.init(notificationCenter: .default)
    }

    init(notificationCenter: NotificationCenter) {
        self.notificationCenter = notificationCenter
        super.init()
        observePopoverLifecycle()
    }

    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
    }

    func register(probeView: NSView) {
        self.probeView = probeView
        if let popover, containsProbe(popover) {
            popoverWindow = probeView.window ?? popover.contentViewController?.view.window
        }
    }

    func requestFullPlayer(
        closePopover: () -> Void,
        openFullPlayer: @escaping () -> Void
    ) {
        guard transition.requestFullPlayer() else { return }
        pendingAction = openFullPlayer
        closePopover()
    }

    private func observePopoverLifecycle() {
        observers = [
            notificationCenter.addObserver(
                forName: NSPopover.didShowNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self,
                          let shownPopover = notification.object as? NSPopover,
                          self.containsProbe(shownPopover) else { return }
                    self.popover = shownPopover
                    self.popoverWindow = self.probeView?.window
                        ?? shownPopover.contentViewController?.view.window
                }
            },
            notificationCenter.addObserver(
                forName: NSPopover.willCloseNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self,
                          let closingPopover = notification.object as? NSPopover else { return }
                    if self.popover == nil, self.containsProbe(closingPopover) {
                        self.popover = closingPopover
                        self.popoverWindow = self.probeView?.window
                            ?? closingPopover.contentViewController?.view.window
                    }
                    guard closingPopover === self.popover else { return }
                    self.transition.popoverWillClose()
                }
            },
            notificationCenter.addObserver(
                forName: NSPopover.didCloseNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self,
                          let closedPopover = notification.object as? NSPopover,
                          closedPopover === self.popover else { return }
                    self.finishPopoverClose()
                }
            }
        ]
    }

    private func containsProbe(_ candidate: NSPopover) -> Bool {
        guard let probeView,
              let contentView = candidate.contentViewController?.view else { return false }
        return probeView === contentView || probeView.isDescendant(of: contentView)
    }

    private func finishPopoverClose() {
        let shouldOpenFullPlayer = transition.popoverDidClose()
        let action = shouldOpenFullPlayer ? pendingAction : nil
        pendingAction = nil
        popover = nil
        popoverWindow = nil
        action?()
    }
}

struct MiniPlayerPopoverProbe: NSViewRepresentable {
    let handoff: MiniPlayerPopoverHandoff

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        handoff.register(probeView: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        handoff.register(probeView: nsView)
    }
}
