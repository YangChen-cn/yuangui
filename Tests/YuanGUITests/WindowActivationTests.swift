import AppKit
import XCTest
@testable import YuanGUI

final class WindowActivationTests: XCTestCase {
    @MainActor
    func testMusicPlayerMovesToTheActiveSpaceWhenReused() {
        let behavior = MusicWindowController.windowCollectionBehavior

        XCTAssertTrue(behavior.contains(.moveToActiveSpace))
        XCTAssertFalse(behavior.contains(.canJoinAllSpaces))
    }

    func testWindowPresentationWaitsForApplicationActivation() {
        XCTAssertFalse(ApplicationWindowActivator.canPresentWindow(isApplicationActive: false))
        XCTAssertTrue(ApplicationWindowActivator.canPresentWindow(isApplicationActive: true))
    }

    @MainActor
    func testWindowPresentationOrdersFrontAndRetriesBeforeMakingKey() async throws {
        let notificationCenter = NotificationCenter()
        var isActive = false
        var activationAttempts = 0
        let activator = ApplicationWindowActivator(
            notificationCenter: notificationCenter,
            retryDelays: [.milliseconds(1)],
            isApplicationActive: { isActive },
            activateApplication: {
                activationAttempts += 1
                if activationAttempts == 2 { isActive = true }
            }
        )
        let window = NSWindow()

        activator.present(window, makeMain: false)
        XCTAssertTrue(window.isVisible)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(activationAttempts, 2)
        XCTAssertTrue(window.isVisible)
        window.orderOut(nil)
    }

    @MainActor
    func testOutsideClickUsesExactPopoverWindowIdentity() {
        let popoverWindow = NSWindow()
        let otherWindow = NSWindow()

        XCTAssertFalse(MiniPlayerOutsideClickEventMonitor.shouldDismiss(
            eventWindow: popoverWindow,
            popoverWindow: popoverWindow
        ))
        XCTAssertTrue(MiniPlayerOutsideClickEventMonitor.shouldDismiss(
            eventWindow: otherWindow,
            popoverWindow: popoverWindow
        ))
        XCTAssertTrue(MiniPlayerOutsideClickEventMonitor.shouldDismiss(
            eventWindow: nil,
            popoverWindow: popoverWindow
        ))
    }

    @MainActor
    func testPopoverHandoffRunsActionForMatchingDidCloseWithoutWillClose() {
        let notificationCenter = NotificationCenter()
        let outsideClickMonitor = RecordingMiniPlayerOutsideClickMonitor()
        let handoff = MiniPlayerPopoverHandoff(
            notificationCenter: notificationCenter,
            outsideClickMonitor: outsideClickMonitor
        )
        let popover = NSPopover()
        let unrelatedPopover = NSPopover()
        let contentView = NSView(frame: .zero)
        let probeView = NSView(frame: .zero)
        contentView.addSubview(probeView)
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = contentView
        let popoverWindow = NSWindow(contentViewController: popover.contentViewController!)
        handoff.register(probeView: probeView, onOutsideClick: {})

        notificationCenter.post(name: NSPopover.didShowNotification, object: popover)
        XCTAssertTrue(outsideClickMonitor.popoverWindow === popoverWindow)
        var events: [String] = []
        handoff.requestFullPlayer(
            closePopover: { events.append("close") },
            openFullPlayer: { events.append("open") }
        )

        XCTAssertEqual(events, ["close"])
        notificationCenter.post(name: NSPopover.didCloseNotification, object: unrelatedPopover)
        XCTAssertEqual(events, ["close"])
        notificationCenter.post(name: NSPopover.didCloseNotification, object: popover)
        XCTAssertEqual(events, ["close", "open"])
        XCTAssertTrue(outsideClickMonitor.didStop)
        notificationCenter.post(name: NSPopover.didCloseNotification, object: popover)
        XCTAssertEqual(events, ["close", "open"])
    }

    @MainActor
    func testPopoverHandoffMatchesDidShowThatPrecedesProbeRegistration() {
        let notificationCenter = NotificationCenter()
        let outsideClickMonitor = RecordingMiniPlayerOutsideClickMonitor()
        let handoff = MiniPlayerPopoverHandoff(
            notificationCenter: notificationCenter,
            outsideClickMonitor: outsideClickMonitor
        )
        let popover = NSPopover()
        let contentView = NSView(frame: .zero)
        let probeView = NSView(frame: .zero)
        contentView.addSubview(probeView)
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = contentView
        let popoverWindow = NSWindow(contentViewController: popover.contentViewController!)

        notificationCenter.post(name: NSPopover.didShowNotification, object: popover)
        handoff.register(probeView: probeView, onOutsideClick: {})

        XCTAssertTrue(outsideClickMonitor.popoverWindow === popoverWindow)
        var events: [String] = []
        handoff.requestFullPlayer(
            closePopover: { events.append("close") },
            openFullPlayer: { events.append("open") }
        )
        notificationCenter.post(name: NSPopover.didCloseNotification, object: popover)

        XCTAssertEqual(events, ["close", "open"])
    }

    @MainActor
    func testPopoverHandoffKeepsIntentUntilLateProbeRegistration() {
        let notificationCenter = NotificationCenter()
        let handoff = MiniPlayerPopoverHandoff(
            notificationCenter: notificationCenter,
            outsideClickMonitor: RecordingMiniPlayerOutsideClickMonitor()
        )
        let popover = NSPopover()
        let contentView = NSView(frame: .zero)
        let probeView = NSView(frame: .zero)
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = contentView
        _ = NSWindow(contentViewController: popover.contentViewController!)
        notificationCenter.post(name: NSPopover.didShowNotification, object: popover)

        var events: [String] = []
        handoff.requestFullPlayer(
            closePopover: { events.append("close") },
            openFullPlayer: { events.append("open") }
        )
        XCTAssertEqual(events, ["close"])

        contentView.addSubview(probeView)
        handoff.register(probeView: probeView, onOutsideClick: {})
        notificationCenter.post(name: NSPopover.willCloseNotification, object: popover)
        notificationCenter.post(name: NSPopover.didCloseNotification, object: popover)

        XCTAssertEqual(events, ["close", "open"])
    }

    @MainActor
    func testPopoverHandoffCompletesRepeatedOpenCloseCycles() {
        let notificationCenter = NotificationCenter()
        let handoff = MiniPlayerPopoverHandoff(
            notificationCenter: notificationCenter,
            outsideClickMonitor: RecordingMiniPlayerOutsideClickMonitor()
        )
        var events: [String] = []

        for cycle in 1...2 {
            let popover = NSPopover()
            let contentView = NSView(frame: .zero)
            let probeView = NSView(frame: .zero)
            contentView.addSubview(probeView)
            popover.contentViewController = NSViewController()
            popover.contentViewController?.view = contentView
            _ = NSWindow(contentViewController: popover.contentViewController!)

            notificationCenter.post(name: NSPopover.didShowNotification, object: popover)
            handoff.register(probeView: probeView, onOutsideClick: {})
            handoff.requestFullPlayer(
                closePopover: { events.append("close-\(cycle)") },
                openFullPlayer: { events.append("open-\(cycle)") }
            )
            notificationCenter.post(name: NSPopover.didCloseNotification, object: popover)
        }

        XCTAssertEqual(events, ["close-1", "open-1", "close-2", "open-2"])
    }

    @MainActor
    func testOutsideClickDismissesOnlyTheMiniPlayer() {
        let notificationCenter = NotificationCenter()
        let outsideClickMonitor = RecordingMiniPlayerOutsideClickMonitor()
        let handoff = MiniPlayerPopoverHandoff(
            notificationCenter: notificationCenter,
            outsideClickMonitor: outsideClickMonitor
        )
        let popover = NSPopover()
        let contentView = NSView(frame: .zero)
        let probeView = NSView(frame: .zero)
        contentView.addSubview(probeView)
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = contentView
        _ = NSWindow(contentViewController: popover.contentViewController!)
        var dismissCount = 0
        handoff.register(probeView: probeView) { dismissCount += 1 }

        notificationCenter.post(name: NSPopover.didShowNotification, object: popover)
        outsideClickMonitor.dismiss()

        XCTAssertEqual(dismissCount, 1)
    }
}

@MainActor
private final class RecordingMiniPlayerOutsideClickMonitor: MiniPlayerOutsideClickMonitoring {
    weak var popoverWindow: NSWindow?
    var onDismiss: (() -> Void)?
    var didStop = false

    func start(popoverWindow: NSWindow, onDismiss: @escaping () -> Void) {
        self.popoverWindow = popoverWindow
        self.onDismiss = onDismiss
        didStop = false
    }

    func stop() {
        didStop = true
        popoverWindow = nil
        onDismiss = nil
    }

    func dismiss() {
        onDismiss?()
    }
}
