import AppKit
import Foundation

struct AppleMusicSnapshot: Equatable {
    var isRunning: Bool
    var track: MusicTrack?
    var state: MusicPlaybackState
    var position: TimeInterval
    var volume: Double
}

enum AppleMusicControlError: LocalizedError {
    case notRunning
    case automationDenied
    case script(String)

    var errorDescription: String? {
        switch self {
        case .notRunning: return "Music App 尚未运行"
        case .automationDenied: return "没有控制 Music App 的权限，请在系统设置的“隐私与安全性 → 自动化”中允许 YuanGUI。"
        case .script(let message): return message
        }
    }
}

@MainActor
final class AppleMusicController: MusicPlaybackControlling {
    private(set) var hasRequestedAccess = false
    private var cachedArtworkTrackID: String?
    private var cachedArtworkURL: URL?

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    func openMusic() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Music.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    func requestSnapshot() throws -> AppleMusicSnapshot {
        guard isRunning else {
            return AppleMusicSnapshot(isRunning: false, track: nil, state: .stopped, position: 0, volume: 1)
        }
        hasRequestedAccess = true
        let descriptor = try execute("""
        tell application "Music"
            set stateText to (player state as text)
            set currentPosition to player position
            set currentVolume to sound volume
            set trackName to ""
            set trackArtist to ""
            set trackAlbum to ""
            set trackDuration to 0
            try
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set trackDuration to duration of current track
            end try
            return {stateText, currentPosition, currentVolume, trackName, trackArtist, trackAlbum, trackDuration}
        end tell
        """)
        let stateText = descriptor.atIndex(1)?.stringValue ?? "stopped"
        let position = descriptor.atIndex(2)?.doubleValue ?? 0
        let volume = Double(descriptor.atIndex(3)?.int32Value ?? 100) / 100
        let title = descriptor.atIndex(4)?.stringValue ?? ""
        let artist = descriptor.atIndex(5)?.stringValue ?? ""
        let album = descriptor.atIndex(6)?.stringValue
        let duration = descriptor.atIndex(7)?.doubleValue ?? 0
        let state: MusicPlaybackState = stateText == "playing" ? .playing : (stateText == "paused" ? .paused : .stopped)
        let trackID = "\(title)|\(artist)|\(Int(duration))"
        let track = title.isEmpty ? nil : MusicTrack.appleMusic(
            title: title,
            artist: artist.isEmpty ? "未知歌手" : artist,
            album: album,
            duration: duration,
            coverURL: artworkURL(for: trackID)
        )
        return AppleMusicSnapshot(isRunning: true, track: track, state: state, position: position, volume: volume)
    }

    private func artworkURL(for trackID: String) -> URL? {
        if cachedArtworkTrackID == trackID { return cachedArtworkURL }
        cachedArtworkTrackID = trackID
        cachedArtworkURL = nil

        let scripts = [
            "tell application \"Music\" to return raw data of artwork 1 of current track",
            "tell application \"Music\" to return data of artwork 1 of current track"
        ]
        for source in scripts {
            guard let descriptor = try? execute(source),
                  let image = NSImage(data: descriptor.data),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { continue }
            do {
                let directory = try artworkDirectory()
                let file = directory.appendingPathComponent("apple-\(stableHash(trackID)).png")
                try png.write(to: file, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                cachedArtworkURL = file
                return file
            } catch { continue }
        }
        return nil
    }

    private func artworkDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent("YuanGUI/Music/Artwork", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func stableHash(_ value: String) -> String {
        let hash = value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    func playPause() { try? command("playpause") }
    func pause() { guard isRunning else { return }; try? command("pause") }
    func previous() { try? command("previous track") }
    func next() { try? command("next track") }
    func seek(to position: TimeInterval) { try? command("set player position to \(max(0, position))") }
    func setVolume(_ volume: Double) { try? command("set sound volume to \(Int(min(max(volume, 0), 1) * 100))") }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func command(_ body: String) throws {
        guard isRunning else { throw AppleMusicControlError.notRunning }
        hasRequestedAccess = true
        _ = try execute("tell application \"Music\" to \(body)")
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source),
              let result = script.executeAndReturnError(&error) as NSAppleEventDescriptor? else {
            let number = error?[NSAppleScript.errorNumber] as? Int
            if number == -1743 { throw AppleMusicControlError.automationDenied }
            throw AppleMusicControlError.script(
                error?[NSAppleScript.errorMessage] as? String ?? "Music App 暂时没有返回播放信息"
            )
        }
        return result
    }
}
