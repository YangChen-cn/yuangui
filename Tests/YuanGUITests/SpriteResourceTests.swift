import AppKit
import XCTest
@testable import YuanGUI

final class SpriteResourceTests: XCTestCase {
    func testTaskSpritesLoadForEveryCharacterAtExpectedSize() throws {
        let files = [
            "15-eat-trash-1", "15-eat-trash-2", "15-eat-trash-3",
            "18-maintenance-scan", "19-maintenance-success"
        ]

        for mode in PetMode.allCases {
            for file in files {
                let action = PetAction(file: file, label: "test")
                let image = try XCTUnwrap(SpriteLoader.image(mode: mode, action: action), "Missing \(mode.resourceFolder)/\(file).png")
                XCTAssertEqual(image.size.width, 512, accuracy: 0.5)
                XCTAssertEqual(image.size.height, 512, accuracy: 0.5)
                let representation = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
                XCTAssertTrue(representation.hasAlpha, "Expected alpha channel in \(mode.resourceFolder)/\(file).png")
            }
        }
    }
}
