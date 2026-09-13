import Foundation
import Darwin

/// A separate process group makes cancellation include uv/Python workers.
final class PDFProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t = 0

    func run(_ executable: URL, arguments: [String], environment: [String: String] = [:],
             progress: @escaping @Sendable (String) async -> Void = { _ in }) async throws -> String {
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("stdout")
        let errors = directory.appendingPathComponent("stderr")
        try launch(executable, arguments: arguments, environment: environment, output: output, errors: errors)
        return try await withTaskCancellationHandler {
            var lastOutput = ""
            while true {
                if Task.isCancelled { cancel() }
                if let status = poll() {
                    try Task.checkCancellation()
                    let text = Self.readTail(output)
                    guard status == 0 else {
                        throw PDFConversionError.process(Self.readTail(errors), text)
                    }
                    return text
                }
                let text = Self.readTail(output)
                if text != lastOutput {
                    lastOutput = text
                    await progress(text)
                }
                // Cancellation is handled by killing/reaping the group, not by abandoning waitpid.
                try? await Task.sleep(for: .milliseconds(150))
            }
        } onCancel: { self.cancel() }
    }

    private func launch(_ executable: URL, arguments: [String], environment: [String: String],
                        output: URL, errors: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        guard pid == 0 else { throw PDFConversionError.message("pdf.error.busy") }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, output.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, errors.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        var values = ProcessInfo.processInfo.environment
        // Do not inherit user Python startup hooks or package search paths.
        values.removeValue(forKey: "PYTHONPATH")
        values.removeValue(forKey: "PYTHONHOME")
        values.merge(environment) { _, new in new }
        let envp = values.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var child: pid_t = 0
        let result = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in
                posix_spawn(&child, executable.path, &actions, &attributes, args.baseAddress!, env.baseAddress!)
            }
        }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(result)) }
        pid = child
    }

    private func poll() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        guard pid > 0 else { return -1 }
        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        guard result != 0 else { return nil }
        if result < 0 && errno == EINTR { return nil }
        // Also reap any workers which outlived the direct child.
        kill(-pid, SIGKILL)
        pid = 0
        return result < 0 ? -1 : status
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        if pid > 0 { kill(-pid, SIGKILL) }
    }

    private static func readTail(_ url: URL) -> String {
        guard let file = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? file.close() }
        let size = (try? file.seekToEnd()) ?? 0
        try? file.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        return String(decoding: (try? file.readToEnd()) ?? Data(), as: UTF8.self)
    }
}

enum PDFConversionError: LocalizedError {
    case message(String)
    case process(String, String)

    var errorDescription: String? {
        switch self {
        case .message(let key): return AppLocalizer.string(key)
        case .process(let diagnostic, let output):
            for line in output.split(separator: "\n").reversed() {
                if let data = String(line).data(using: .utf8),
                   let event = try? JSONDecoder().decode(PDFWorkerEvent.self, from: data),
                   let error = event.error { return AppLocalizer.string("pdf.error.\(error)") }
            }
            return AppLocalizer.string("pdf.error.process") + "\n" + String(diagnostic.suffix(2_000))
        }
    }
}

struct PDFWorkerEvent: Decodable {
    var stage: String?
    var error: String?
    var probe: PDFProbe?
}
