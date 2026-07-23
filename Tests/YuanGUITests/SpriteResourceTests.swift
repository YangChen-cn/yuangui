import AppKit
import XCTest
@testable import YuanGUI

final class SpriteResourceTests: XCTestCase {
    func testDistributedAppFindsPackagedSpriteWithoutSwiftPMBuildDirectory() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let spriteDirectory = temporaryRoot
            .appendingPathComponent("Sprites/Test", isDirectory: true)
        let spriteURL = spriteDirectory.appendingPathComponent("idle.png")
        try FileManager.default.createDirectory(
            at: spriteDirectory,
            withIntermediateDirectories: true
        )
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: spriteURL)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let resolvedURL = SpriteLoader.resourceURL(
            file: "idle",
            subdirectory: "Sprites/Test",
            roots: [temporaryRoot],
            mainBundleURL: URL(fileURLWithPath: "/Applications/YuanGUI.app")
        )

        XCTAssertEqual(resolvedURL, spriteURL)
    }

    func testTaskSpritesLoadForEveryCharacterAtExpectedSize() throws {
        let files = [
            "15-eat-trash-1", "15-eat-trash-2", "15-eat-trash-3",
            "18-maintenance-scan", "19-maintenance-success", "20-listening"
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

    func testVCCCuriousSpriteHasNoDetachedRightEdgePixels() throws {
        let image = try XCTUnwrap(SpriteLoader.image(
            mode: .vcc,
            action: PetAction(file: "03-curious", label: "test")
        ))
        let representation = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        for x in 450..<representation.pixelsWide {
            for y in 0..<representation.pixelsHigh {
                XCTAssertEqual(
                    representation.colorAt(x: x, y: y)?.alphaComponent ?? 0,
                    0,
                    accuracy: 0.001,
                    "Unexpected detached pixel at (\(x), \(y))"
                )
            }
        }
    }

    func testVisibleBoundsFollowEachActionsOpaqueArtwork() {
        let yuanGui = SpriteLoader.normalizedVisibleBounds(
            mode: .yuanGui,
            action: PetMode.yuanGui.actions[0]
        )
        let vcc = SpriteLoader.normalizedVisibleBounds(
            mode: .vcc,
            action: PetMode.vcc.actions[0]
        )

        XCTAssertGreaterThanOrEqual(yuanGui.minY, 0)
        XCTAssertLessThanOrEqual(yuanGui.maxY, 1)
        XCTAssertGreaterThanOrEqual(vcc.minY, 0)
        XCTAssertLessThanOrEqual(vcc.maxY, 1)
        XCTAssertLessThan(vcc.height, yuanGui.height)
        XCTAssertNotEqual(vcc, yuanGui)
    }
}
