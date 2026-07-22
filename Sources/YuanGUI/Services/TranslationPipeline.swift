import Foundation

struct TranslationSegment: Hashable, Sendable, Identifiable {
    let id: String
    let sourceText: String

    init(id: String, sourceText: String) {
        self.id = id
        self.sourceText = sourceText
    }
}

struct TranslationSegmentResult: Equatable, Sendable, Identifiable {
    let id: String
    let sourceText: String
    let translatedText: String
    let detectedSourceLanguage: String?

    init(
        id: String,
        sourceText: String,
        translatedText: String,
        detectedSourceLanguage: String? = nil
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.detectedSourceLanguage = detectedSourceLanguage
    }
}

struct TranslationRequest: Hashable, Sendable {
    let segments: [TranslationSegment]
    let targetLanguage: QuickToolLanguage
    let engine: TranslationEngine
    /// Identifies engine configuration without including secrets such as API keys.
    let configurationVariant: String

    init(
        segments: [TranslationSegment],
        targetLanguage: QuickToolLanguage,
        engine: TranslationEngine,
        configurationVariant: String = ""
    ) {
        self.segments = segments
        self.targetLanguage = targetLanguage
        self.engine = engine
        self.configurationVariant = configurationVariant
    }
}

enum TranslationJobState: Equatable, Sendable {
    case idle
    case preparing
    case translating(completed: Int, total: Int)
    case layingOut
    case ready
    case cancelled
    case failed(String)
}

actor TranslationPipeline {
    static let shared = TranslationPipeline()

    typealias Operation = @Sendable () async throws -> [TranslationSegmentResult]

    private struct CacheEntry: Sendable {
        let value: [TranslationSegmentResult]
        var lastAccess: ContinuousClock.Instant
        let estimatedBytes: Int
    }

    private let clock = ContinuousClock()
    private let expiration: Duration
    private let maximumEntryCount: Int
    private let maximumEstimatedBytes: Int
    private var cache: [TranslationRequest: CacheEntry] = [:]
    private var inFlight: [TranslationRequest: Task<[TranslationSegmentResult], Error>] = [:]

    init(
        expiration: Duration = .seconds(600),
        maximumEntryCount: Int = 100,
        maximumEstimatedBytes: Int = 5 * 1_024 * 1_024
    ) {
        self.expiration = expiration
        self.maximumEntryCount = maximumEntryCount
        self.maximumEstimatedBytes = maximumEstimatedBytes
    }

    func translate(
        _ request: TranslationRequest,
        operation: @escaping Operation
    ) async throws -> [TranslationSegmentResult] {
        try Task.checkCancellation()
        removeExpiredEntries()
        if var cached = cache[request] {
            cached.lastAccess = clock.now
            cache[request] = cached
            TranslationPerformance.logCacheHit(engine: request.engine)
            return cached.value
        }
        if let existing = inFlight[request] {
            TranslationPerformance.logRequestCoalesced(engine: request.engine)
            let value = try await existing.value
            try Task.checkCancellation()
            return value
        }

        let task = Task(priority: .userInitiated) {
            try await TranslationPerformance.measure(.translation) {
                try await operation()
            }
        }
        inFlight[request] = task
        do {
            let value = try await task.value
            inFlight[request] = nil
            cache[request] = CacheEntry(
                value: value,
                lastAccess: clock.now,
                estimatedBytes: Self.estimatedBytes(for: request, value: value)
            )
            trimCache()
            try Task.checkCancellation()
            return value
        } catch {
            inFlight[request] = nil
            throw error
        }
    }

    func removeAllCachedTranslations() {
        cache.removeAll(keepingCapacity: false)
    }

    func cachedEntryCount() -> Int { cache.count }

    private func removeExpiredEntries() {
        let now = clock.now
        cache = cache.filter { now - $0.value.lastAccess < expiration }
    }

    private func trimCache() {
        var byteCount = cache.values.reduce(0) { $0 + $1.estimatedBytes }
        while cache.count > maximumEntryCount || byteCount > maximumEstimatedBytes {
            guard let oldest = cache.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else { break }
            byteCount -= oldest.value.estimatedBytes
            cache.removeValue(forKey: oldest.key)
        }
    }

    private static func estimatedBytes(
        for request: TranslationRequest,
        value: [TranslationSegmentResult]
    ) -> Int {
        let sourceBytes = request.segments.reduce(0) { $0 + $1.sourceText.utf8.count + $1.id.utf8.count }
        let resultBytes = value.reduce(0) {
            $0 + $1.sourceText.utf8.count + $1.translatedText.utf8.count + $1.id.utf8.count
        }
        return sourceBytes + resultBytes + 256
    }
}
