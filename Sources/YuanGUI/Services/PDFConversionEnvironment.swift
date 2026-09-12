import Foundation
import CryptoKit
import Darwin

struct PDFConversionEnvironment: Sendable {
    static let revision = "markitdown-0.1.7-v1"
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

    func install(progress: @escaping @Sendable (String) async -> Void) async throws {
        if isReady { return }
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
        if isReady { return }
        // Partial environments are never considered ready. Keep the final venv path stable:
        // Python launchers contain absolute paths and cannot be relocated after creation.
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer { if !completed { try? fm.removeItem(at: directory) } }
        await progress("download")
        #if arch(arm64)
        let architecture = "aarch64"
        let checksum = "7e6ddb9316acc00f2296c82ff4d99977870ee34b2f0ddcae9444d714db9364ed"
        #else
        let architecture = "x86_64"
        let checksum = "5e287ef61cb6a9b61b3a83fef124fd143e400468a7dac794230147a810e17119"
        #endif
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
        await progress("verify")
        _ = try await runner.run(python, arguments: ["-I", "-c", "import importlib.metadata, pdfplumber; from markitdown import MarkItDown; assert importlib.metadata.version('markitdown') == '0.1.7'; MarkItDown(enable_plugins=False)"])
        try Task.checkCancellation()
        try Data(Self.revision.utf8).write(to: directory.appendingPathComponent("ready"), options: .atomic)
        completed = true
        try? fm.removeItem(at: archive)
        try? fm.removeItem(at: directory.appendingPathComponent("cache"))
    }
}
