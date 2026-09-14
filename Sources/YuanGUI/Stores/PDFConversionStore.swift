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
    /// Hybrid OCR: on by default, and the engine recognizes only the pages that need it,
    /// so a page with its own text layer never reaches the recognition stack.
    @Published private(set) var ocrEnabled: Bool
    /// Repeated page headers and footers are dropped unless the user opts out.
    @Published private(set) var removeHeaderFooter: Bool
    /// Whether the current task, or the finished result on screen, ran with OCR.
    @Published private(set) var ocrApplied = false
    /// Cheap document facts for the selected file, once a runtime is installed.
    @Published private(set) var probe: PDFProbe?
    /// Bytes of disk the installed runtime occupies.
    @Published private(set) var runtimeBytes: Int64 = 0
    var inputKind: DocumentInput? { source.flatMap(DocumentInput.init(url:)) }
    var canConvert: Bool { source != nil && (isReady || inputKind?.needsRuntime == false) }
    private var task: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    /// Startup housekeeping holds the install lock, so both install and uninstall wait
    /// for it instead of racing it and reporting a spurious "busy" failure.
    private var housekeeping: Task<Void, Never>?
    private var generation = UUID()
    private var closed = false
    private let environment: PDFConversionEnvironment
    private let defaults: UserDefaults
    private let installOperation: @Sendable (@escaping @Sendable (String) async -> Void) async throws -> Void
    private let convertOperation: @Sendable (URL, PDFConversionOptions, @escaping @Sendable (String) async -> Void) async throws -> PDFConversionResult
    private let probeOperation: @Sendable (URL) async throws -> PDFProbe
    private let uninstallOperation: @Sendable () async throws -> Void

    private static let ocrKey = "pdf.ocrEnabled"
    private static let marginsKey = "pdf.removeHeaderFooter"

    init(environment: PDFConversionEnvironment = PDFConversionEnvironment(),
         defaults: UserDefaults = .standard,
         install: (@Sendable (@escaping @Sendable (String) async -> Void) async throws -> Void)? = nil,
         convert: (@Sendable (URL, PDFConversionOptions, @escaping @Sendable (String) async -> Void) async throws -> PDFConversionResult)? = nil,
         probe: (@Sendable (URL) async throws -> PDFProbe)? = nil,
         uninstall: (@Sendable () async throws -> Void)? = nil) {
        self.environment = environment
        self.defaults = defaults
        isReady = environment.isReady
        ocrEnabled = defaults.object(forKey: Self.ocrKey) as? Bool ?? true
        removeHeaderFooter = defaults.object(forKey: Self.marginsKey) as? Bool ?? true
        installOperation = install ?? { progress in try await environment.install(progress: progress) }
        convertOperation = convert ?? { url, options, progress in
            try await PDFConversionService(environment: environment).convert(url, options: options, progress: progress)
        }
        probeOperation = probe ?? { url in
            try await PDFConversionService(environment: environment).probe(url)
        }
        uninstallOperation = uninstall ?? { try environment.uninstall() }
        // A previous app version may have left its runtime behind; only this version's
        // revision is needed, and it is verified before anything is removed.
        if isReady {
            let environment = environment
            housekeeping = Task.detached(priority: .utility) { environment.removeStaleRevisions() }
            refreshRuntimeBytes()
        }
    }

    /// Measuring walks the whole runtime, so it runs off the main thread.
    private func refreshRuntimeBytes() {
        let environment = environment
        let token = generation
        Task { [weak self] in
            let bytes = await Task.detached(priority: .utility) { environment.sizeOnDisk() }.value
            guard let self, !closed, generation == token else { return }
            runtimeBytes = bytes
        }
    }

    func uninstall() {
        guard !isBusy, !closed else { return }
        clearResult()
        probeTask?.cancel()
        probe = nil
        start(stage: "uninstalling") { [self] token in
            await housekeeping?.value
            guard accepts(token) else { return }
            try await uninstallOperation()
            guard accepts(token) else { return }
            isReady = environment.isReady
            runtimeBytes = environment.sizeOnDisk()
            stage = "uninstalled"
        }
    }

    func setOCR(_ enabled: Bool) {
        guard !isBusy else { return }
        ocrEnabled = enabled
        defaults.set(enabled, forKey: Self.ocrKey)
    }

    func setRemoveHeaderFooter(_ enabled: Bool) {
        guard !isBusy else { return }
        removeHeaderFooter = enabled
        defaults.set(enabled, forKey: Self.marginsKey)
    }

    func select(_ urls: [URL]) {
        guard !isBusy, !closed else { return }
        guard urls.count == 1, let url = urls.first, DocumentInput(url: url) != nil else {
            error = AppLocalizer.string("pdf.error.selection")
            return
        }
        clearResult()
        source = url
        error = nil
        stage = "idle"
        elapsed = 0
        startProbe(url)
    }

    func install() {
        start(stage: "download") { [self] token in
            await housekeeping?.value
            guard accepts(token) else { return }
            try await installOperation { [weak self] stage in await self?.update(stage, token: token) }
            guard accepts(token) else { return }
            isReady = environment.isReady
            if !isReady { throw PDFConversionError.message("pdf.error.resources") }
            stage = "ready"
            refreshRuntimeBytes()
            if let source { startProbe(source) }
        }
    }

    func convert() {
        guard !isBusy, !closed, canConvert, let source else { return }
        clearResult()
        probeTask?.cancel()
        let useOCR = inputKind == .image || (inputKind?.showsPageOptions == true && ocrEnabled)
        ocrApplied = useOCR
        let options = PDFConversionOptions(useOCR: useOCR, removeHeaderFooter: inputKind?.showsPageOptions == true && removeHeaderFooter)
        start(stage: "text") { [self] token in
            let converted = try await convertOperation(source, options) { [weak self] stage in await self?.update(stage, token: token) }
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
        probeTask?.cancel()
        task?.cancel()
        if !isBusy { clearResult() }
    }

    /// Reading the document is cheap and only needs PyMuPDF, so it runs while the user
    /// is still deciding. Failures stay silent: converting reports them properly.
    private func startProbe(_ url: URL) {
        probeTask?.cancel()
        probe = nil
        guard isReady, !closed, DocumentInput(url: url)?.needsRuntime == true else { return }
        let operation = probeOperation
        probeTask = Task { [self] in
            let facts = try? await operation(url)
            guard !closed, !Task.isCancelled, source == url else { return }
            probe = facts
            if facts?.encrypted == true, error == nil {
                error = AppLocalizer.string("pdf.error.locked")
            }
        }
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
