import AppKit
import SwiftUI

@MainActor
final class MiniPlayerPopoverHandoff: NSObject, ObservableObject {
    private let notificationCenter: NotificationCenter
    private let outsideClickMonitor: MiniPlayerOutsideClickMonitoring
    private var observers: [NSObjectProtocol] = []
    private weak var probeView: NSView?
    private var popover: NSPopover?
    private weak var popoverWindow: NSWindow?
    private var pendingPopover: NSPopover?
    private var pendingAction: (() -> Void)?
    private var outsideDismissAction: (() -> Void)?

    override convenience init() {
        self.init(
            notificationCenter: .default,
            outsideClickMonitor: MiniPlayerOutsideClickEventMonitor()
        )
    }

    convenience init(notificationCenter: NotificationCenter) {
        self.init(
            notificationCenter: notificationCenter,
            outsideClickMonitor: MiniPlayerOutsideClickEventMonitor()
        )
    }

    init(
        notificationCenter: NotificationCenter,
        outsideClickMonitor: MiniPlayerOutsideClickMonitoring
    ) {
        self.notificationCenter = notificationCenter
        self.outsideClickMonitor = outsideClickMonitor
        super.init()
        observePopoverLifecycle()
    }

    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
    }

    func register(probeView: NSView, onOutsideClick: @escaping () -> Void) {
        self.probeView = probeView
        outsideDismissAction = onOutsideClick
        capturePopoverWindowIfAvailable()
    }

    func requestFullPlayer(
        closePopover: () -> Void,
        openFullPlayer: @escaping () -> Void
    ) {
        guard pendingPopover == nil, let popover else { return }
        pendingPopover = popover
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
                    self.capturePopoverWindowIfAvailable()
                }
            },
            notificationCenter.addObserver(
                forName: NSPopover.didCloseNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self,
                          let closedPopover = notification.object as? NSPopover else { return }
                    self.finishPopoverClose(closedPopover)
                }
            }
        ]
    }

    private func containsProbe(_ candidate: NSPopover) -> Bool {
        guard let probeView,
              let contentView = candidate.contentViewController?.view else { return false }
        return probeView === contentView || probeView.isDescendant(of: contentView)
    }

    private func capturePopoverWindowIfAvailable() {
        guard let popover,
              containsProbe(popover),
              let window = probeView?.window
                ?? popover.contentViewController?.view.window else { return }
        guard popoverWindow !== window else { return }
        popoverWindow = window
        outsideClickMonitor.start(popoverWindow: window) { [weak self] in
            self?.outsideDismissAction?()
        }
    }

    private func finishPopoverClose(_ closedPopover: NSPopover) {
        if closedPopover === popover {
            outsideClickMonitor.stop()
            popover = nil
            popoverWindow = nil
        }

        guard closedPopover === pendingPopover else { return }
        let action = pendingAction
        pendingPopover = nil
        pendingAction = nil
        action?()
    }
}

struct MiniPlayerPopoverProbe: NSViewRepresentable {
    let handoff: MiniPlayerPopoverHandoff
    let onOutsideClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        handoff.register(probeView: view, onOutsideClick: onOutsideClick)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        handoff.register(probeView: nsView, onOutsideClick: onOutsideClick)
    }
}
