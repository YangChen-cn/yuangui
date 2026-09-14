import Foundation

/// What the window asks the local converter to do. The defaults are the window's own:
/// hybrid OCR, which the engine applies only to pages that need it, and repeated page
/// headers and footers dropped. The worker's command line defaults to no OCR, so the
/// service passes `--ocr` for these options.
struct PDFConversionOptions: Sendable, Equatable {
    var useOCR = true
    var removeHeaderFooter = true
}

/// Cheap facts gathered before the Layout model is loaded.
struct PDFProbe: Codable, Sendable, Equatable {
    let pages: Int
    let encrypted: Bool
    let textPages: Int
    let sampledPages: Int
    let scanned: Bool
}

struct PDFConversionResult: Sendable {
    struct Manifest: Codable, Sendable {
        let images: [String]
        let emptyText: Bool
    }
    let directory: URL
    let manifest: Manifest
    let preview: String
    let truncated: Bool
    var bodyURL: URL { directory.appendingPathComponent("body.md") }
}

struct PDFConversionService: Sendable {
    /// Must match the directory the worker writes its picture links against.
    static let assetsDirectory = "_assets"
    let environment: PDFConversionEnvironment

    func probe(_ source: URL) async throws -> PDFProbe {
        try Self.validate(source)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let output = try await PDFProcessRunner().run(environment.python,
            arguments: ["-I", try PDFConversionEnvironment.resource("convert.py").path, "--probe", source.path])
        guard let probe = Self.event(in: output, \.probe) else {
            throw PDFConversionError.message("pdf.error.invalid")
        }
        return probe
    }

    func convert(_ source: URL, options: PDFConversionOptions,
                 progress: @escaping @Sendable (String) async -> Void) async throws -> PDFConversionResult {
        try Self.validate(source)
        if let kind = DocumentInput(url: source), !kind.needsRuntime {
            return try await NativeDocumentConversionService().convert(source, progress: progress)
        }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("YuanGUI-PDF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var success = false
        defer { if !success { try? FileManager.default.removeItem(at: directory) } }
        var arguments = ["-I", try PDFConversionEnvironment.resource("convert.py").path, source.path, directory.path]
        if options.useOCR { arguments.append("--ocr") }
        if !options.removeHeaderFooter { arguments.append("--keep-header-footer") }
        _ = try await PDFProcessRunner().run(environment.python,
            arguments: arguments,
            progress: { output in
                guard let event = Self.lastEvent(in: output), let stage = event.stage else { return }
                await progress(stage)
            })
        try Task.checkCancellation()
        let manifest = try JSONDecoder().decode(PDFConversionResult.Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("result.json")))
        let (preview, truncated) = try Self.readPreview(directory.appendingPathComponent("body.md"))
        success = true
        return PDFConversionResult(directory: directory, manifest: manifest, preview: preview, truncated: truncated)
    }

    private static func validate(_ source: URL) throws {
        guard DocumentInput(url: source) != nil else {
            throw PDFConversionError.message("pdf.error.invalid")
        }
    }

    /// The worker reports progress continuously, so only the newest decoded event counts.
    private static func lastEvent(in output: String) -> PDFWorkerEvent? {
        for line in output.split(separator: "\n").reversed() {
            if let event = try? JSONDecoder().decode(PDFWorkerEvent.self, from: Data(line.utf8)) { return event }
        }
        return nil
    }

    private static func event<T>(in output: String, _ extract: (PDFWorkerEvent) -> T?) -> T? {
        for line in output.split(separator: "\n").reversed() {
            if let event = try? JSONDecoder().decode(PDFWorkerEvent.self, from: Data(line.utf8)),
               let value = extract(event) { return value }
        }
        return nil
    }

    static func readPreview(_ url: URL, limit: Int = 200_000) throws -> (String, Bool) {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        // Read a bounded prefix. A Unicode scalar takes at most four UTF-8 bytes.
        let data = try file.read(upToCount: limit * 4 + 4) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        let prefix = String(text.prefix(limit))
        let total = try file.seekToEnd()
        return (prefix, text.count > limit || total > UInt64(data.count))
    }

    static func export(_ result: PDFConversionResult, to folder: URL, name: String) throws -> URL {
        let fm = FileManager.default
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let staging = folder.appendingPathComponent(".yuangui-pdf-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let base = name.isEmpty ? "Document" : URL(fileURLWithPath: name).lastPathComponent
        for index in 0..<10_000 {
            try Task.checkCancellation()
            let candidate = index == 0 ? base : "\(base) (\(index))"
            let md = folder.appendingPathComponent(candidate + ".md")
            let assetsName = candidate + "_assets"
            let assets = folder.appendingPathComponent(assetsName)
            guard !fm.fileExists(atPath: md.path), !fm.fileExists(atPath: assets.path) else { continue }
            let stagedMD = staging.appendingPathComponent("document.md")
            let stagedAssets = staging.appendingPathComponent("assets")
            try fm.createDirectory(at: stagedAssets, withIntermediateDirectories: false)
            // Pictures are linked as "_assets/<file>" while previewing; the export points
            // them at the sibling folder that actually receives them.
            let encodedAssets = assetsName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
            let body = try String(contentsOf: result.bodyURL, encoding: .utf8)
            try Data(body.replacingOccurrences(of: "](\(assetsDirectory)/", with: "](\(encodedAssets)/").utf8)
                .write(to: stagedMD)
            for image in result.manifest.images {
                try Task.checkCancellation()
                guard URL(fileURLWithPath: image).lastPathComponent == image else {
                    throw PDFConversionError.message("pdf.error.invalid")
                }
                try fm.copyItem(at: result.directory.appendingPathComponent(image), to: stagedAssets.appendingPathComponent(image))
            }
            var movedAssets = false
            do {
                try Task.checkCancellation()
                if !result.manifest.images.isEmpty {
                    try fm.moveItem(at: stagedAssets, to: assets)
                    movedAssets = true
                }
                try fm.moveItem(at: stagedMD, to: md)
                return md
            } catch {
                if movedAssets { try? fm.removeItem(at: assets) }
                throw error
            }
        }
        throw PDFConversionError.message("pdf.error.export")
    }
}
