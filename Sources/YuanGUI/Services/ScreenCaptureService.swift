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
        case .permissionDenied: "需要开启“屏幕与系统音频录制”权限后才能截图。"
        case .displayUnavailable: "找不到选区所在的显示器。"
        case .invalidSelection: "截图区域太小，请重新选择。"
        }
    }
}

struct ScreenshotSelection: Equatable {
    let globalRect: CGRect
    let displayID: CGDirectDisplayID
    let displayFrame: CGRect
    let scale: CGFloat

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

struct ScreenCaptureService: ScreenCapturing {
    func capture(_ selection: ScreenshotSelection, excludingWindowNumbers: Set<Int>) async throws -> CapturedScreenshot {
        guard selection.globalRect.width >= 3, selection.globalRect.height >= 3 else {
            throw ScreenCaptureServiceError.invalidSelection
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenCaptureServiceError.permissionDenied
        }

        let content = try await ScreenCaptureContentCache.shared.content(
            containingWindowNumbers: excludingWindowNumbers
        )
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw ScreenCaptureServiceError.displayUnavailable
        }
        let excludedWindows = content.windows.filter { excludingWindowNumbers.contains(Int($0.windowID)) }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = selection.displayLocalSourceRect
        configuration.width = max(1, Int((selection.globalRect.width * selection.scale).rounded()))
        configuration.height = max(1, Int((selection.globalRect.height * selection.scale).rounded()))
        configuration.showsCursor = false
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
