import Foundation
import OSLog

enum TranslationPerformanceStage: String, Sendable {
    case capture
    case ocr
    case grouping
    case translation
    case layout
    case background
    case presentation
}

enum TranslationPerformance {
    private static let logger = Logger(subsystem: "com.yuangui.app", category: "TranslationPerformance")

    static func measure<T: Sendable>(
        _ stage: TranslationPerformanceStage,
        operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let value = try await operation()
            log(stage: stage, duration: start.duration(to: clock.now), outcome: "success")
            return value
        } catch {
            log(stage: stage, duration: start.duration(to: clock.now), outcome: "failure")
            throw error
        }
    }

    static func measureSync<T>(
        _ stage: TranslationPerformanceStage,
        operation: () throws -> T
    ) rethrows -> T {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let value = try operation()
            log(stage: stage, duration: start.duration(to: clock.now), outcome: "success")
            return value
        } catch {
            log(stage: stage, duration: start.duration(to: clock.now), outcome: "failure")
            throw error
        }
    }

    static func logCacheHit(engine: TranslationEngine) {
        logger.debug("cache_hit engine=\(engine.rawValue, privacy: .public)")
    }

    static func logRequestCoalesced(engine: TranslationEngine) {
        logger.debug("request_coalesced engine=\(engine.rawValue, privacy: .public)")
    }

    private static func log(stage: TranslationPerformanceStage, duration: Duration, outcome: String) {
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        logger.info("stage=\(stage.rawValue, privacy: .public) duration_ms=\(milliseconds, format: .fixed(precision: 2), privacy: .public) outcome=\(outcome, privacy: .public)")
    }
}
