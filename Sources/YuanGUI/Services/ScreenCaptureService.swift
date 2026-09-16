import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum ScreenCapturePermissionState: Equatable {
    case granted
    case notDeterminedOrDenied
}

enum ScreenCaptureServiceError: LocalizedError {
    case permissionDenied
    case displayUnavailable
    case invalidSelection

    var errorDescription: String? {
        switch self {
        case .permissionDenied: AppLocalizer.string("需要开启“屏幕与系统音频录制”权限后才能截图。")
        case .displayUnavailable: AppLocalizer.string("找不到选区所在的显示器。")
        case .invalidSelection: AppLocalizer.string("截图区域太小，请重新选择。")
        }
    }
}

struct ScreenshotSelection: Equatable {
    let globalRect: CGRect
    let displayID: CGDirectDisplayID
    let displayFrame: CGRect
    let scale: CGFloat
    var action: CaptureAction = .confirm
    var windowID: CGWindowID? = nil

    var displayLocalSourceRect: CGRect {
        CGRect(
            x: globalRect.minX - displayFrame.minX,
            y: displayFrame.maxY - globalRect.maxY,
            width: globalRect.width,
            height: globalRect.height
        )
    }
}

struct CapturedScreenshot {
    let image: CGImage
    let selection: ScreenshotSelection
}

protocol ScreenCapturing {
    func capture(_ selection: ScreenshotSelection, excludingWindowNumbers: Set<Int>) async throws -> CapturedScreenshot
}

enum ScreenCapturePermission {
    static var state: ScreenCapturePermissionState {
        CGPreflightScreenCaptureAccess() ? .granted : .notDeterminedOrDenied
    }

    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    @MainActor
    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// One window as the capture policy sees it. Deliberately carries no owner
/// information: capture decides by window number, never by owning process.
struct CaptureWindowDescriptor: Equatable {
    let windowNumber: Int
    let isOnScreen: Bool
    let layer: Int
    let frame: CGRect
}

/// Which windows a capture may include and which it must hide.
///
/// YuanGUI's own windows — pet, dashboard, settings, chat history, diary,
/// music, the screenshot editor and pinned shots — are ordinary capture
/// targets, so a screenshot (and a window capture) can show YuanGUI itself.
/// The only windows hidden from a capture are the running session's overlays
/// (the selection panels and their HUD), matched by window number.
enum CaptureWindowPolicy {
    static func isSelectable(_ window: CaptureWindowDescriptor, overlays: Set<Int>) -> Bool {
        !overlays.contains(window.windowNumber)
            && window.isOnScreen
            && window.layer == 0
            && window.frame.width >= 3
            && window.frame.height >= 3
    }

    static func isHiddenFromRegionCapture(_ window: CaptureWindowDescriptor, overlays: Set<Int>) -> Bool {
        overlays.contains(window.windowNumber)
    }
}

struct ScreenCaptureService: ScreenCapturing {
    static func selectableWindows(excludingWindowNumbers overlays: Set<Int>) async throws -> [CaptureWindowTarget] {
        let content = try await ScreenCaptureContentCache.shared.content(containingWindowNumbers: overlays)
        // CGWindow ordering is front-to-back; SCK's window array has no ordering contract.
        let order = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return content.windows.filter {
            CaptureWindowPolicy.isSelectable(Self.descriptor(for: $0), overlays: overlays)
        }.sorted { (rank[$0.windowID] ?? .max) < (rank[$1.windowID] ?? .max) }
            .map { CaptureWindowTarget(id: $0.windowID, frame: $0.frame) }
    }

    private static func descriptor(for window: SCWindow) -> CaptureWindowDescriptor {
        CaptureWindowDescriptor(
            windowNumber: Int(window.windowID),
            isOnScreen: window.isOnScreen,
            layer: window.windowLayer,
            frame: window.frame
        )
    }

    func capture(_ selection: ScreenshotSelection, excludingWindowNumbers overlays: Set<Int>) async throws -> CapturedScreenshot {
        guard selection.globalRect.width >= 3, selection.globalRect.height >= 3 else {
            throw ScreenCaptureServiceError.invalidSelection
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenCaptureServiceError.permissionDenied
        }

        let content = try await ScreenCaptureContentCache.shared.content(
            containingWindowNumbers: overlays
        )
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw ScreenCaptureServiceError.displayUnavailable
        }
        let filter: SCContentFilter
        if let id = selection.windowID {
            guard let window = content.windows.first(where: { $0.windowID == id }),
                  !overlays.contains(Int(id)) else {
                throw ScreenCaptureServiceError.invalidSelection
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else {
            let excludedWindows = content.windows.filter {
                CaptureWindowPolicy.isHiddenFromRegionCapture(Self.descriptor(for: $0), overlays: overlays)
            }
            filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        }
        let configuration = SCStreamConfiguration()
        if selection.windowID == nil { configuration.sourceRect = selection.displayLocalSourceRect }
        configuration.width = max(1, Int((selection.globalRect.width * selection.scale).rounded()))
        configuration.height = max(1, Int((selection.globalRect.height * selection.scale).rounded()))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.scalesToFit = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        return CapturedScreenshot(image: image, selection: selection)
    }
}

private actor ScreenCaptureContentCache {
    static let shared = ScreenCaptureContentCache()

    private let clock = ContinuousClock()
    private var cached: (content: SCShareableContent, createdAt: ContinuousClock.Instant)?

    func content(containingWindowNumbers required: Set<Int>) async throws -> SCShareableContent {
        if let cached,
           clock.now - cached.createdAt < .seconds(2),
           required.isSubset(of: Set(cached.content.windows.map { Int($0.windowID) })) {
            return cached.content
        }
        let fresh = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        cached = (fresh, clock.now)
        return fresh
    }
}
