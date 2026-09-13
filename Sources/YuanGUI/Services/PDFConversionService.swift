import Foundation

struct PDFConversionResult: Sendable {
    struct Manifest: Codable, Sendable {
        struct Image: Codable, Sendable { let name: String; let page: Int }
        let images: [Image]
        let failedPages: [Int]
        let emptyText: Bool
    }
    let directory: URL
    let manifest: Manifest
    let preview: String
    let truncated: Bool
    var bodyURL: URL { directory.appendingPathComponent("body.md") }
}

struct PDFConversionService: Sendable {
    let environment: PDFConversionEnvironment

    func convert(_ source: URL, useOCR: Bool = false,
                 progress: @escaping @Sendable (String) async -> Void) async throws -> PDFConversionResult {
        guard source.isFileURL, source.pathExtension.lowercased() == "pdf" else {
            throw PDFConversionError.message("pdf.error.invalid")
        }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("YuanGUI-PDF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var success = false
        defer { if !success { try? FileManager.default.removeItem(at: directory) } }
        var arguments = ["-I", try PDFConversionEnvironment.resource("convert.py").path, source.path, directory.path]
        if useOCR { arguments.append("--ocr") }
        _ = try await PDFProcessRunner().run(environment.python,
            arguments: arguments,
            progress: { output in
                guard let line = output.split(separator: "\n").last,
                      let event = try? JSONDecoder().decode(PDFWorkerEvent.self, from: Data(line.utf8)),
                      let stage = event.stage else { return }
                await progress(stage)
            })
        try Task.checkCancellation()
        let manifest = try JSONDecoder().decode(PDFConversionResult.Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("result.json")))
        let (preview, truncated) = try Self.readPreview(directory.appendingPathComponent("body.md"))
        success = true
        return PDFConversionResult(directory: directory, manifest: manifest, preview: preview, truncated: truncated)
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
            try fm.copyItem(at: result.bodyURL, to: stagedMD)
            let stagedAssets = staging.appendingPathComponent("assets")
            try fm.createDirectory(at: stagedAssets, withIntermediateDirectories: false)
            let file = try FileHandle(forWritingTo: stagedMD)
            do {
                try file.seekToEnd()
                for image in result.manifest.images {
                    try Task.checkCancellation()
                    guard URL(fileURLWithPath: image.name).lastPathComponent == image.name else {
                        throw PDFConversionError.message("pdf.error.invalid")
                    }
                    try fm.copyItem(at: result.directory.appendingPathComponent(image.name), to: stagedAssets.appendingPathComponent(image.name))
                    let relative = (assetsName + "/" + image.name).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
                    try file.write(contentsOf: Data("\n\n![Page \(image.page)](<\(relative)>)".utf8))
                }
                try file.close()
            } catch { try? file.close(); throw error }
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
