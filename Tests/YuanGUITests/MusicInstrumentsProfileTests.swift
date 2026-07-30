import AppKit
import SwiftUI
import XCTest
@testable import YuanGUI

@MainActor
final class MusicInstrumentsProfileTests: XCTestCase {
    func testImportProgressDoesNotInvalidateMountedMusicProgressView() async throws {
        guard ProcessInfo.processInfo.environment["YUANGUI_MUSIC_INSTRUMENTS"] == "1" else {
            throw XCTSkip("Set YUANGUI_MUSIC_INSTRUMENTS=1 while recording the SwiftUI template")
        }

        let suiteName = "MusicInstrumentsProfileTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let music = MusicFeature(defaults: defaults)
        let window = NSWindow(
            contentRect: NSRect(x: 20, y: 20, width: 900, height: 620),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0.01
        window.contentView = NSHostingView(rootView: MusicPlayerView(music: music))
        window.orderFrontRegardless()

        try await Task.sleep(for: .milliseconds(150))
        for completed in 1...100 {
            music.bilibiliImportStore.completedCount = completed
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(150))

        window.close()
        await music.shutdown()
        defaults.removePersistentDomain(forName: suiteName)
    }
}
