import AppKit
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

    @MainActor
    func testKeyActionsUseAuthoredSixFrameSequencesAndChargingFallback() {
        for mode in PetMode.allCases {
            let idle = mode.actions[0]
            XCTAssertEqual(SpriteLoader.frames(mode: mode, action: idle).count, 6)
            XCTAssertEqual(SpriteLoader.frames(mode: mode, action: mode.chatAction).count, 6)
            XCTAssertEqual(
                SpriteLoader.frames(mode: mode, action: PetAction(file: "11-charging", label: "test")).count,
                5
            )
        }
    }

    @MainActor
    func testDisabledMotionUsesOriginalStaticArtworkInsteadOfSequenceFrame() {
        for mode in PetMode.allCases {
            let idle = mode.actions[0]
            XCTAssertEqual(
                SpriteLoader.displayFrames(mode: mode, action: idle, playsSequence: false).count,
                1
            )
            XCTAssertEqual(
                SpriteLoader.displayFrames(mode: mode, action: idle, playsSequence: true).count,
                6
            )
        }
    }

    @MainActor
    func testChatSequencesMatchIdleVisualSize() throws {
        for mode in PetMode.allCases {
            let idleFrames = SpriteLoader.frames(mode: mode, action: mode.actions[0])
            let chatFrames = SpriteLoader.frames(mode: mode, action: mode.chatAction)
            let idleMass = median(try idleFrames.map(alphaMass))
            let chatMass = median(try chatFrames.map(alphaMass))

            XCTAssertEqual(
                chatMass / idleMass,
                1,
                accuracy: 0.04,
                "\(mode.title) chatting frames should not zoom relative to idle"
            )
        }
    }

    private func alphaMass(_ image: NSImage) throws -> Double {
        let representation = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        let data = try XCTUnwrap(representation.bitmapData)
        XCTAssertEqual(representation.bitsPerSample, 8)
        XCTAssertFalse(representation.isPlanar)
        let samples = representation.samplesPerPixel
        let alphaOffset = representation.bitmapFormat.contains(.alphaFirst) ? 0 : samples - 1
        var total = 0
        for y in 0..<representation.pixelsHigh {
            let row = data.advanced(by: y * representation.bytesPerRow)
            for x in 0..<representation.pixelsWide {
                total += Int(row[x * samples + alphaOffset])
            }
        }
        return Double(total) / 255
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let midpoint = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[midpoint - 1] + sorted[midpoint]) / 2
        }
        return sorted[midpoint]
    }

    private func action(_ file: String) -> PetAction {
        PetAction(file: file, label: "test")
    }
}
