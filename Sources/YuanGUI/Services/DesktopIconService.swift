import Foundation

@MainActor
protocol DesktopIconManaging: AnyObject {
    func areDesktopIconsVisible() -> Bool
    func setDesktopIconsVisible(_ visible: Bool) throws
}

enum DesktopIconServiceError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let detail):
            return detail.isEmpty ? "Finder 设置更新失败" : detail
        }
    }
}

@MainActor
final class DesktopIconService: DesktopIconManaging {
    func areDesktopIconsVisible() -> Bool {
        let key = "CreateDesktop" as CFString
        let applicationID = "com.apple.finder" as CFString
        CFPreferencesAppSynchronize(applicationID)
        guard let value = CFPreferencesCopyAppValue(key, applicationID) else { return true }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String {
            return !["0", "false", "no"].contains(text.lowercased())
        }
        return true
    }

    func setDesktopIconsVisible(_ visible: Bool) throws {
        let write = run(
            executable: "/usr/bin/defaults",
            arguments: [
                "write", "com.apple.finder", "CreateDesktop", "-bool",
                visible ? "true" : "false"
            ]
        )
        guard write.status == 0 else {
            throw DesktopIconServiceError.commandFailed(write.output)
        }

        let restart = run(executable: "/usr/bin/killall", arguments: ["Finder"])
        guard restart.status == 0 else {
            throw DesktopIconServiceError.commandFailed(
                restart.output.isEmpty ? "设置已保存，但 Finder 未能自动重新启动" : restart.output
            )
        }
    }

    private func run(executable: String, arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
