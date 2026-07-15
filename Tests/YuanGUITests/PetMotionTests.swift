import XCTest
@testable import YuanGUI

final class PetMotionTests: XCTestCase {
    func testEveryActionResolvesToADeclaredMotionStyle() {
        for mode in PetMode.allCases {
            let actions = mode.actions + [
                mode.chatAction,
                PetAction(file: "09-low-battery", label: "test"),
                PetAction(file: "10-memory-pressure", label: "test"),
                PetAction(file: "11-charging", label: "test"),
                PetAction(file: "12-rainy", label: "test"),
                PetAction(file: "13-bedtime", label: "test"),
                PetAction(file: "15-eat-trash-1", label: "test"),
                PetAction(file: "15-eat-trash-2", label: "test"),
                PetAction(file: "15-eat-trash-3", label: "test"),
                PetAction(file: "18-maintenance-scan", label: "test"),
                PetAction(file: "19-maintenance-success", label: "test")
            ]

            XCTAssertEqual(actions.count, 19)
            for action in actions {
                XCTAssertTrue(PetMotionStyle.allCases.contains(PetMotionProfile.style(for: action)))
            }
        }
    }

    func testMotionProfilesMatchActionIntent() {
        XCTAssertEqual(PetMotionProfile.style(for: action("01-idle")), .gentle)
        XCTAssertEqual(PetMotionProfile.style(for: action("02-wave")), .wave)
        XCTAssertEqual(PetMotionProfile.style(for: action("04-hop")), .bounce)
        XCTAssertEqual(PetMotionProfile.style(for: action("04-pounce")), .pounce)
        XCTAssertEqual(PetMotionProfile.style(for: action("07-sleep")), .sleepy)
        XCTAssertEqual(PetMotionProfile.style(for: action("11-charging")), .pulse)
        XCTAssertEqual(PetMotionProfile.style(for: action("15-eat-trash-2")), .chomp)
    }

    private func action(_ file: String) -> PetAction {
        PetAction(file: file, label: "test")
    }
}
