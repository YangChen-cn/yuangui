import XCTest
@testable import YuanGUI

final class WindowActivationTests: XCTestCase {
    func testActivationFinishesOnlyForAnActiveVisibleKeyWindow() {
        let scenarios: [(
            isApplicationActive: Bool,
            isWindowVisible: Bool,
            isWindowKey: Bool,
            requiresMainWindow: Bool,
            isWindowMain: Bool,
            expected: Bool
        )] = [
            (true, true, true, false, false, true),
            (true, true, true, true, true, true),
            (false, true, true, false, false, false),
            (true, false, true, false, false, false),
            (true, true, false, false, false, false),
            (true, true, true, true, false, false)
        ]

        for scenario in scenarios {
            XCTAssertEqual(
                ApplicationWindowActivator.shouldFinishActivation(
                    isApplicationActive: scenario.isApplicationActive,
                    isWindowVisible: scenario.isWindowVisible,
                    isWindowKey: scenario.isWindowKey,
                    requiresMainWindow: scenario.requiresMainWindow,
                    isWindowMain: scenario.isWindowMain
                ),
                scenario.expected
            )
        }
    }

    func testOnlyActivatingWindowsRecoverApplicationActivation() {
        XCTAssertTrue(ApplicationWindowActivator.shouldRecoverActivationForKeyWindow(
            isApplicationActive: false,
            isWindowVisible: true,
            isNonactivatingPanel: false
        ))
        XCTAssertFalse(ApplicationWindowActivator.shouldRecoverActivationForKeyWindow(
            isApplicationActive: true,
            isWindowVisible: true,
            isNonactivatingPanel: false
        ))
        XCTAssertFalse(ApplicationWindowActivator.shouldRecoverActivationForKeyWindow(
            isApplicationActive: false,
            isWindowVisible: true,
            isNonactivatingPanel: true
        ))
        XCTAssertFalse(ApplicationWindowActivator.shouldRecoverActivationForKeyWindow(
            isApplicationActive: false,
            isWindowVisible: false,
            isNonactivatingPanel: false
        ))
    }
}
