import AppKit
import XCTest
@testable import YuanGUI

final class WindowActivationTests: XCTestCase {
    func testWindowPresentationWaitsForApplicationActivation() {
        XCTAssertFalse(ApplicationWindowActivator.canPresentWindow(isApplicationActive: false))
        XCTAssertTrue(ApplicationWindowActivator.canPresentWindow(isApplicationActive: true))
    }

    func testMiniPlayerHandoffRequiresRealCloseLifecycle() {
        var transition = MiniPlayerPopoverTransition()

        XCTAssertTrue(transition.requestFullPlayer())
        XCTAssertFalse(transition.popoverDidClose())

        XCTAssertTrue(transition.requestFullPlayer())
        transition.popoverWillClose()
        XCTAssertTrue(transition.popoverDidClose())
    }

    func testMiniPlayerHandoffConsumesOneRequestOnlyOnce() {
        var transition = MiniPlayerPopoverTransition()

        XCTAssertTrue(transition.requestFullPlayer())
        XCTAssertFalse(transition.requestFullPlayer())
        transition.popoverWillClose()
        XCTAssertTrue(transition.popoverDidClose())
        XCTAssertFalse(transition.popoverDidClose())
    }

    func testOrdinaryPopoverCloseDoesNotOpenFullPlayer() {
        var transition = MiniPlayerPopoverTransition()

        transition.popoverWillClose()
        XCTAssertFalse(transition.popoverDidClose())
    }

    @MainActor
    func testPopoverHandoffRunsActionOnlyAfterTrackedPopoverDidClose() {
        let notificationCenter = NotificationCenter()
        let handoff = MiniPlayerPopoverHandoff(notificationCenter: notificationCenter)
        let popover = NSPopover()
        let contentView = NSView(frame: .zero)
        let probeView = NSView(frame: .zero)
        contentView.addSubview(probeView)
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = contentView
        handoff.register(probeView: probeView)

        notificationCenter.post(name: NSPopover.didShowNotification, object: popover)
        var events: [String] = []
        handoff.requestFullPlayer(
            closePopover: { events.append("close") },
            openFullPlayer: { events.append("open") }
        )

        XCTAssertEqual(events, ["close"])
        notificationCenter.post(name: NSPopover.willCloseNotification, object: popover)
        XCTAssertEqual(events, ["close"])
        notificationCenter.post(name: NSPopover.didCloseNotification, object: popover)
        XCTAssertEqual(events, ["close", "open"])
        notificationCenter.post(name: NSPopover.didCloseNotification, object: popover)
        XCTAssertEqual(events, ["close", "open"])
    }
}
