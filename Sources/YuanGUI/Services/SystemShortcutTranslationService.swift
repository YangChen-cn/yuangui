import Darwin
import Foundation

protocol SystemShortcutTranslationServicing: Sendable {
    func translate(_ text: String, target: QuickToolLanguage) async throws -> String
}

struct SystemShortcutTranslationService: SystemShortcutTranslationServicing, Sendable {
    static let shortcutName = "YuanGUI.Translate"
    static var installURL: URL? {
        installURL(resourceRoots: defaultResourceRoots)
    }

    static func installURL(resourceRoots: [URL]) -> URL? {
        let fileName = "\(shortcutName).shortcut"
        let resourceBundleName = "YuanGUI_YuanGUI.bundle"
        for root in resourceRoots {
            let candidates = [
                root.appendingPathComponent(fileName),
                root.appendingPathComponent(resourceBundleName, isDirectory: true)
                    .appendingPathComponent(fileName)
            ]
            if let url = candidates.first(where: { FileManager.default.isReadableFile(atPath: $0.path) }) {
                return url
            }
        }
        return nil
    }

    func translate(_ text: String, target: QuickToolLanguage) async throws -> String {
        let input = try Self.inputData(text: text, target: target)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue(label: "com.yuangui.shortcut-translation", qos: .userInitiated).async {
                continuation.resume(with: Result { try Self.runShortcut(with: input) })
            }
        }
    }

    private static func runShortcut(with input: Data) throws -> String {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", shortcutName]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            throw SystemShortcutTranslationError.unavailable(error.localizedDescription)
        }

        let timeout = ShortcutProcessTimeout()
        let timeoutWork = DispatchWorkItem { timeout.stop(process) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20, execute: timeoutWork)
        defer { timeoutWork.cancel() }

        inputPipe.fileHandleForWriting.write(input)
        try? inputPipe.fileHandleForWriting.close()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if timeout.didTimeOut {
            throw SystemShortcutTranslationError.timedOut
        }
        let output = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            if output.localizedCaseInsensitiveContains("not found")
                || output.localizedCaseInsensitiveContains("could not find") {
                throw SystemShortcutTranslationError.notInstalled
            }
            throw SystemShortcutTranslationError.failed(output.isEmpty ? "退出状态 \(process.terminationStatus)" : output)
        }
        if output.hasPrefix("Error:") {
            throw SystemShortcutTranslationError.failed(
                output.replacingOccurrences(of: "Error:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard !output.isEmpty else {
            throw SystemShortcutTranslationError.emptyResult
        }
        return output
    }

    static func inputData(text: String, target: QuickToolLanguage) throws -> Data {
        return try JSONSerialization.data(withJSONObject: [
            "detectFrom": "",
            "detectTo": target.shortcutIdentifier,
            "text": text
        ], options: [.sortedKeys])
    }

    private static var defaultResourceRoots: [URL] {
        var roots = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.deletingLastPathComponent(),
            Bundle.main.executableURL?.deletingLastPathComponent()
        ].compactMap { $0 }
        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            if let resourceURL = bundle.resourceURL { roots.append(resourceURL) }
            roots.append(bundle.bundleURL)
            roots.append(bundle.bundleURL.deletingLastPathComponent())
        }
        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}

private extension QuickToolLanguage {
    var shortcutIdentifier: String {
        switch self {
        case .simplifiedChinese: "zh_CN"
        case .english: "en_US"
        case .japanese: "ja_JP"
        case .korean: "ko_KR"
        case .french: "fr_FR"
        case .german: "de_DE"
        case .spanish: "es_ES"
        }
    }
}

enum SystemShortcutTranslationError: LocalizedError {
    case notInstalled
    case unavailable(String)
    case failed(String)
    case timedOut
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .notInstalled: "尚未安装系统翻译快捷指令，请在快捷工具设置中点击“获取快捷指令”。"
        case let .unavailable(message): "无法启动系统快捷指令：\(message)"
        case let .failed(message): "系统快捷指令翻译失败：\(message)"
        case .timedOut: "系统快捷指令在 20 秒内没有返回结果，请检查快捷指令权限后重试。"
        case .emptyResult: "系统快捷指令没有返回译文。"
        }
    }
}

private final class ShortcutProcessTimeout: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false

    var didTimeOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }

    func stop(_ process: Process) {
        lock.lock()
        guard process.isRunning else {
            lock.unlock()
            return
        }
        timedOut = true
        let processID = process.processIdentifier
        process.terminate()
        lock.unlock()

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if process.isRunning { _ = Darwin.kill(processID, SIGKILL) }
        }
    }
}
