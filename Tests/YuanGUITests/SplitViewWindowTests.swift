import XCTest
import AppKit
import SwiftUI
@testable import YuanGUI

/// Regression coverage for the white strip `NavigationSplitView` paints across
/// the top of its window on macOS 26/27 (see `SplitViewWindowChrome`).
final class SplitViewWindowTests: XCTestCase {
    @MainActor func testChromeOnlyTouchesTitlebarTransparency() throws {
        let bare = makeWindow(chrome: false)
        let configured = makeWindow(chrome: true)
        defer { bare.orderOut(nil); configured.orderOut(nil) }

        XCTAssertFalse(bare.titlebarAppearsTransparent)
        XCTAssertTrue(configured.titlebarAppearsTransparent)
        // The fix must not move, resize or inset anything.
        XCTAssertEqual(configured.styleMask, bare.styleMask)
        XCTAssertEqual(configured.contentLayoutRect, bare.contentLayoutRect)
    }

    @MainActor func testConfiguredSplitViewWindowKeepsItsFirstDetailLineVisible() throws {
        let plain = try render(chrome: false)
        let configured = try render(chrome: true)

        // The system sidebar control has to survive the fix.
        XCTAssertTrue(
            configured.toolbarIdentifiers.contains { $0.contains("toggleSidebar") },
            "the split view must keep its sidebar toggle, got \(configured.toolbarIdentifiers)"
        )

        guard let top = configured.lines.first, configured.lines.count >= 2 else {
            return XCTFail("the detail column must draw both fixture lines, got \(configured.lines)")
        }
        // The fixture draws the same headline twice: once against the titlebar,
        // once far enough down to be out of its reach. The strip fades the top
        // one out, so comparing the two lines calibrates the check for the
        // machine it runs on instead of using a fixed pixel budget.
        let reference = configured.lines[configured.lines.count - 1]
        XCTAssertGreaterThan(
            Double(top) / Double(max(reference, 1)), 0.9,
            """
            the first detail line is obscured: \(top) dark pixels against \
            \(reference) for the same line lower down \
            (unconfigured window: \(plain.lines) — a strip is present when these drop)
            """
        )
    }

    // MARK: - Helpers

    @MainActor
    private func makeWindow(chrome: Bool) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        if chrome { SplitViewWindowChrome.apply(to: window) }
        window.contentView = NSHostingView(rootView: SplitViewFixture())
        window.setFrameOrigin(NSPoint(x: 400, y: 400))
        return window
    }

    private struct Measurement {
        let lines: [Int]
        let toolbarIdentifiers: [String]
    }

    /// Groups the dark pixels of the detail column into text lines, top first.
    @MainActor
    private func render(chrome: Bool) throws -> Measurement {
        let window = makeWindow(chrome: chrome)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let settle = Date().addingTimeInterval(0.8)
        while Date() < settle { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }

        let frame = try XCTUnwrap(window.contentView?.superview)
        let rep = try XCTUnwrap(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
        frame.cacheDisplay(in: frame.bounds, to: rep)

        // Only the detail column, so the sidebar and window title stay out.
        let scale = CGFloat(rep.pixelsWide) / frame.bounds.width
        var rowInk = [Int](repeating: 0, count: rep.pixelsHigh)
        for y in 0..<rep.pixelsHigh {
            for x in Int(300 * scale)..<Int(CGFloat(rep.pixelsWide) - 20 * scale) {
                guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let luminance = 0.299 * colour.redComponent + 0.587 * colour.greenComponent + 0.114 * colour.blueComponent
                if luminance < 0.5 { rowInk[y] += 1 }
            }
        }
        var lines: [Int] = []
        var current = 0
        for ink in rowInk {
            if ink > 0 { current += ink } else if current > 0 { lines.append(current); current = 0 }
        }
        if current > 0 { lines.append(current) }
        return Measurement(lines: lines, toolbarIdentifiers: window.toolbar?.items.map(\.itemIdentifier.rawValue) ?? [])
    }
}

private struct SplitViewFixture: View {
    var body: some View {
        NavigationSplitView {
            List(selection: .constant(0)) {
                Text("General").tag(0)
                Text("Pet").tag(1)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SplitViewFixture.headline
                    Spacer().frame(height: 220)
                    SplitViewFixture.headline
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private static let headline = Text("SUMMARY").font(.system(size: 30, weight: .black))
}
