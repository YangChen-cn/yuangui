import Foundation
import CryptoKit
import Darwin

#if !arch(arm64)
#error("YuanGUI's PDF conversion runtime supports Apple Silicon Macs only.")
#endif

struct PDFConversionEnvironment: Sendable {
    static let revision = "pymupdf-layout-1.28.2-ocr-v1"
    let root: URL

    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("YuanGUI/PDFConversion")) {
        self.root = root
    }

    var directory: URL { root.appendingPathComponent(Self.revision) }
    var python: URL { directory.appendingPathComponent("venv/bin/python3") }
    var isReady: Bool {
        FileManager.default.isExecutableFile(atPath: python.path)
            && FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready").path)
    }

    static func resource(_ name: String) throws -> URL {
        let bundleName = "YuanGUI_YuanGUI.bundle"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(bundleName)
        ].compactMap { $0 }
        for bundleURL in candidates {
            if let bundle = Bundle(url: bundleURL),
               let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "PDFConversion") { return url }
        }
        // Only raw SwiftPM tests may use the generated development-path fallback.
        if AppLocalizer.allowsModuleFallback(for: Bundle.main.bundleURL),
           let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "PDFConversion") { return url }
        throw PDFConversionError.message("pdf.error.resources")
    }

    /// Bytes occupied by the installed runtime, or zero when nothing is installed.
    func sizeOnDisk() -> Int64 {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true, let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    /// Remove the installed runtime, freeing the space it occupies. The install lock is
    /// taken first, so a running installer is never deleted from under itself.
    func uninstall() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return }
        let descriptor = Darwin.open(root.appendingPathComponent(".install-lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw PDFConversionError.message("pdf.error.busy") }
        defer { flock(descriptor, LOCK_UN) }
        try Task.checkCancellation()
        // Keep the lock inode and its parent alive. Unlinking a locked file lets a
        // concurrent installer create a different inode and acquire a second lock.
        for child in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            guard child.lastPathComponent != ".install-lock" else { continue }
            try fm.removeItem(at: child)
        }
    }

    /// Delete the parts of the pinned engine that this configuration never reads. The
    /// audit behind this list: the layout model, its image-feature model and the V4-EP
    /// table-grid model are the only ONNX models loaded (traced through
    /// `onnxruntime.InferenceSession` at import and during conversion of text, table,
    /// figure, scan and 400-page documents). Alternate feature sets and table-grid
    /// versions are reachable only through constructor arguments YuanGUI never passes,
    /// and the package has no environment or file based override. `sympy`, `mpmath` and
    /// `networkx` are declared by onnxruntime and pymupdf-layout but imported only by
    /// onnxruntime's model tooling, which is not part of inference. OpenCV, Shapely,
    /// Pillow, PyYAML, pyclipper and RapidOCR stay: the optional OCR pass imports them.
    private static let unusedRuntimePaths = [
        "uv-aarch64-apple-darwin",
        // C headers and static libraries for building against MuPDF, used only by the
        // `pymupdf._mupdf_devel()` helper that this app never calls.
        "venv/lib/python3.12/site-packages/pymupdf/mupdf-devel",
        "venv/lib/python3.12/site-packages/sympy",
        "venv/lib/python3.12/site-packages/mpmath",
        "venv/lib/python3.12/site-packages/networkx",
        "venv/lib/python3.12/site-packages/onnxruntime/tools",
        "venv/lib/python3.12/site-packages/onnxruntime/transformers",
        "venv/lib/python3.12/site-packages/onnxruntime/quantization"
    ]

    /// ONNX models kept by name; every other model file and its config is removed.
    private static let usedModels = Set([
        "layout_rf2.4.1+imf1.onnx", "layout_rf2.4.1+imf1.yaml",
        "feature_imf1.onnx", "table_grid_model_v4_ep.onnx"
    ])

    /// Returns the number of bytes removed. Best effort: a file that cannot be removed
    /// only costs disk space, and the install self-test still runs afterwards.
    @discardableResult
    func removeUnusedFiles() -> Int64 {
        let fm = FileManager.default
        var removed: Int64 = 0
        func size(of url: URL) -> Int64 {
            let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
            if let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true {
                return Int64(values.fileSize ?? 0)
            }
            guard let walker = fm.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
            return walker.reduce(into: Int64(0)) { total, item in
                guard let item = item as? URL,
                      let values = try? item.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else { return }
                total += Int64(values.fileSize ?? 0)
            }
        }
        for relative in Self.unusedRuntimePaths {
            let url = directory.appendingPathComponent(relative)
            guard fm.fileExists(atPath: url.path) else { continue }
            let bytes = size(of: url)
            if (try? fm.removeItem(at: url)) != nil { removed += bytes }
        }
        let models = directory.appendingPathComponent("venv/lib/python3.12/site-packages/pymupdf/layout/resources/onnx")
        for url in (try? fm.contentsOfDirectory(at: models, includingPropertiesForKeys: nil)) ?? [] {
            guard !Self.usedModels.contains(url.lastPathComponent) else { continue }
            let bytes = size(of: url)
            if (try? fm.removeItem(at: url)) != nil { removed += bytes }
        }
        return removed
    }

    /// Remove runtime revisions other than the current one, which is installed and
    /// verified. Backs off while another installer holds the lock.
    func removeStaleRevisions() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return }
        let descriptor = Darwin.open(root.appendingPathComponent(".install-lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return }
        defer { flock(descriptor, LOCK_UN) }
        removeRevisionsLocked()
    }

    /// Callers must hold the install lock: it keeps a concurrent installer's working
    /// files out of the way of this removal.
    private func removeRevisionsLocked() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys)) ?? []
        let current = try? directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        for entry in entries where entry.lastPathComponent != directory.lastPathComponent {
            // Only ever remove a sibling revision directory inside this folder, and only
            // one installed before this revision: a newer app version may own it.
            guard let marker = entry.lastPathComponent.range(of: "-v", options: .backwards),
                  !entry.lastPathComponent.hasPrefix("."),
                  marker.upperBound < entry.lastPathComponent.endIndex,
                  entry.lastPathComponent[marker.upperBound...].allSatisfy(\.isNumber),
                  let values = try? entry.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let installed = values.contentModificationDate, let current, installed < current else { continue }
            try? fm.removeItem(at: entry)
        }
    }

    func install(progress: @escaping @Sendable (String) async -> Void) async throws {
        if isReady {
            removeStaleRevisions()
            return
        }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        // A just-closed window may still be reaping its cancelled installer.
        // Do not let a newly opened window remove that installer's working files.
        let descriptor = Darwin.open(root.appendingPathComponent(".install-lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw PDFConversionError.message("pdf.error.busy") }
        defer { flock(descriptor, LOCK_UN) }
        try Task.checkCancellation()
        if isReady {
            removeRevisionsLocked()
            return
        }
        // Partial environments are never considered ready. Keep the final venv path stable:
        // Python launchers contain absolute paths and cannot be relocated after creation.
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer { if !completed { try? fm.removeItem(at: directory) } }
        await progress("download")
        // Apple Silicon only: the pinned runtime has no Intel build.
        let architecture = "aarch64"
        let checksum = "7e6ddb9316acc00f2296c82ff4d99977870ee34b2f0ddcae9444d714db9364ed"
        let archiveName = "uv-\(architecture)-apple-darwin"
        let url = URL(string: "https://github.com/astral-sh/uv/releases/download/0.12.13/\(archiveName).tar.gz")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: url)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == checksum else {
            throw PDFConversionError.message("pdf.error.download")
        }
        let archive = directory.appendingPathComponent("uv.tar.gz")
        try data.write(to: archive)
        let runner = PDFProcessRunner()
        _ = try await runner.run(URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-xzf", archive.path, "-C", directory.path])
        try Task.checkCancellation()
        let uv = directory.appendingPathComponent("\(archiveName)/uv")
        let environment = [
            "UV_PYTHON_INSTALL_DIR": directory.appendingPathComponent("python").path,
            "UV_PYTHON_BIN_DIR": directory.appendingPathComponent("bin").path,
            "UV_CACHE_DIR": directory.appendingPathComponent("cache").path,
            "UV_NO_CONFIG": "1", "UV_PYTHON_PREFERENCE": "only-managed",
            "UV_NO_PROGRESS": "1"
        ]
        await progress("python")
        _ = try await runner.run(uv, arguments: ["python", "install", "--no-bin", "3.12.13"], environment: environment)
        try Task.checkCancellation()
        _ = try await runner.run(uv, arguments: ["venv", "--python", "3.12.13", directory.appendingPathComponent("venv").path], environment: environment)
        await progress("dependencies")
        _ = try await runner.run(uv, arguments: ["pip", "sync", "--python", python.path, "--require-hashes", "--only-binary", ":all:",
                                               try Self.resource("requirements.lock").path], environment: environment)
        try Task.checkCancellation()
        // Drop the installer's own tooling and the engine parts this configuration never
        // reads, then verify what is left: the self-test below runs on the pruned tree.
        await progress("cleanup")
        removeUnusedFiles()
        try Task.checkCancellation()
        await progress("verify")
        _ = try await runner.run(python, arguments: ["-I", try Self.resource("convert.py").path, "--self-test"])
        try Task.checkCancellation()
        try Data(Self.revision.utf8).write(to: directory.appendingPathComponent("ready"), options: .atomic)
        completed = true
        try? fm.removeItem(at: archive)
        try? fm.removeItem(at: directory.appendingPathComponent("cache"))
        // Only now that this revision is verified is any earlier one expendable.
        removeRevisionsLocked()
    }
}
