import AppKit

@MainActor
final class PDFConversionStore: ObservableObject {
    @Published private(set) var source: URL?
    @Published private(set) var isReady: Bool
    @Published private(set) var isBusy = false
    @Published private(set) var stage = "idle"
    @Published private(set) var error: String?
    @Published private(set) var result: PDFConversionResult?
    @Published private(set) var exportedURL: URL?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var startedAt: Date?
    /// Automatic OCR is off unless the user opts in; text PDFs need no recognition.
    @Published private(set) var ocrEnabled: Bool
    /// Whether the current task, or the finished result on screen, ran with OCR.
    @Published private(set) var ocrApplied = false
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var closed = false
    private let environment: PDFConversionEnvironment
    private let defaults: UserDefaults
    private let installOperation: @Sendable (@escaping @Sendable (String) async -> Void) async throws -> Void
    private let convertOperation: @Sendable (URL, Bool, @escaping @Sendable (String) async -> Void) async throws -> PDFConversionResult

    private static let ocrKey = "pdf.ocrEnabled"

    init(environment: PDFConversionEnvironment = PDFConversionEnvironment(),
         defaults: UserDefaults = .standard,
         install: (@Sendable (@escaping @Sendable (String) async -> Void) async throws -> Void)? = nil,
         convert: (@Sendable (URL, Bool, @escaping @Sendable (String) async -> Void) async throws -> PDFConversionResult)? = nil) {
        self.environment = environment
        self.defaults = defaults
        isReady = environment.isReady
        ocrEnabled = defaults.bool(forKey: Self.ocrKey)
        installOperation = install ?? { progress in try await environment.install(progress: progress) }
        convertOperation = convert ?? { url, useOCR, progress in
            try await PDFConversionService(environment: environment).convert(url, useOCR: useOCR, progress: progress)
        }
    }

    func setOCR(_ enabled: Bool) {
        guard !isBusy else { return }
        ocrEnabled = enabled
        defaults.set(enabled, forKey: Self.ocrKey)
    }

    func select(_ urls: [URL]) {
        guard !isBusy, !closed else { return }
        guard urls.count == 1, let url = urls.first, url.isFileURL, url.pathExtension.lowercased() == "pdf" else {
            error = AppLocalizer.string("pdf.error.selection")
            return
        }
        clearResult()
        source = url
        error = nil
        stage = "idle"
        elapsed = 0
    }

    func install() {
        start(stage: "download") { [self] token in
            try await installOperation { [weak self] stage in await self?.update(stage, token: token) }
            guard accepts(token) else { return }
            isReady = environment.isReady
            if !isReady { throw PDFConversionError.message("pdf.error.resources") }
            stage = "ready"
        }
    }

    func convert() {
        guard !isBusy, !closed, isReady, let source else { return }
        clearResult()
        let useOCR = ocrEnabled
        ocrApplied = useOCR
        start(stage: "text") { [self] token in
            let converted = try await convertOperation(source, useOCR) { [weak self] stage in await self?.update(stage, token: token) }
            guard accepts(token) else {
                try? FileManager.default.removeItem(at: converted.directory)
                return
            }
            result = converted
            stage = "finished"
        }
    }

    func export(to folder: URL) {
        guard let result, let source else { return }
        start(stage: "exporting") { [self] token in
            let url = try await Self.exportOffMain(result, folder: folder, name: source.deletingPathExtension().lastPathComponent)
            guard accepts(token) else { return }
            exportedURL = url
            stage = "exported"
        }
    }

    func copy() {
        guard let result else { return }
        start(stage: "copying") { [self] token in
            let text = try await Self.readBody(result.bodyURL)
            guard accepts(token) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            stage = "copied"
        }
    }

    func cancel() { task?.cancel() }

    func close() {
        closed = true
        generation = UUID()
        task?.cancel()
        if !isBusy { clearResult() }
    }

    private func start(stage initialStage: String, operation: @escaping @MainActor (UUID) async throws -> Void) {
        guard !isBusy, !closed else { return }
        let token = UUID()
        generation = token
        isBusy = true
        error = nil
        stage = initialStage
        let started = Date()
        startedAt = started
        task = Task { [self] in
            do { try await operation(token) }
            catch {
                if !closed, generation == token {
                    if Task.isCancelled || error is CancellationError { stage = "cancelled" }
                    else { self.error = error.localizedDescription; stage = "failed" }
                }
            }
            if !closed, generation == token {
                if Task.isCancelled { stage = "cancelled" }
                elapsed = Date().timeIntervalSince(started)
            }
            isBusy = false
            startedAt = nil
            task = nil
            if closed { clearResult() }
        }
    }

    private func accepts(_ token: UUID) -> Bool { !closed && !Task.isCancelled && generation == token }
    private func update(_ value: String, token: UUID) { if accepts(token) { stage = value } }
    private func clearResult() {
        if let result { try? FileManager.default.removeItem(at: result.directory) }
        result = nil
        exportedURL = nil
    }

    nonisolated private static func readBody(_ url: URL) async throws -> String {
        try Task.checkCancellation()
        return try String(contentsOf: url, encoding: .utf8)
    }

    nonisolated private static func exportOffMain(_ result: PDFConversionResult, folder: URL, name: String) async throws -> URL {
        try PDFConversionService.export(result, to: folder, name: name)
    }
}
