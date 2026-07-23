import Foundation
import OSLog

enum RuntimePerformance {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yang.yuangui",
        category: "Performance"
    )

    static func start() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func record(_ operation: StaticString, since start: UInt64) {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        guard elapsed >= 0.25 else { return }
        logger.debug("\(String(describing: operation), privacy: .public) finished in \(elapsed, privacy: .public) ms")
    }
}
