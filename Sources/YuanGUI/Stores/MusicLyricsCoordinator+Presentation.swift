import AppKit
import Foundation

extension MusicLyricsCoordinator {
    func toggleVisible() {
        lyricsVisible.toggle()
        defaults.set(lyricsVisible, forKey: "musicLyricsVisible")
        lyricsPresentation.onVisibilityChanged?()
    }

    func setLightSingAlongEnabled(_ enabled: Bool) {
        lightSingAlongEnabled = enabled
        defaults.set(enabled, forKey: "musicLightSingAlong")
    }

    func setPanelLocked(_ locked: Bool) {
        lyricsPanelLocked = locked
        defaults.set(locked, forKey: "musicLyricsPanelLocked")
        lyricsPresentation.onLockChanged?()
    }

    func setFontSize(_ size: Double) {
        lyricsFontSize = min(max(size, 14), 42)
        defaults.set(lyricsFontSize, forKey: "musicLyricsFontSize")
    }

    func setFontStyle(_ style: LyricsFontStyle) {
        lyricsFontStyle = style
        defaults.set(style.rawValue, forKey: "musicLyricsFontStyle")
    }

    func setColor(_ color: NSColor) {
        guard let color = color.usingColorSpace(.sRGB) else { return }
        lyricsColor = color
        defaults.set(Self.encodeColor(color), forKey: "musicLyricsColor")
    }

    func setShadowEnabled(_ enabled: Bool) {
        lyricsShadowEnabled = enabled
        defaults.set(enabled, forKey: "musicLyricsShadowEnabled")
    }

    func setBackgroundVisible(_ visible: Bool) {
        lyricsBackgroundVisible = visible
        defaults.set(visible, forKey: "musicLyricsBackgroundVisible")
    }

    func setBackgroundOpacity(_ opacity: Double) {
        lyricsBackgroundOpacity = min(max(opacity, 0.12), 0.60)
        defaults.set(lyricsBackgroundOpacity, forKey: "musicLyricsBackgroundOpacity")
    }

    func setOffset(_ offset: TimeInterval) {
        guard !isShuttingDown else { return }
        guard let trackID = currentTrack?.id else { return }
        let clamped = min(max(offset, -30), 30)
        if abs(clamped) < 0.001 {
            lyricOffsets.removeValue(forKey: trackID)
        } else {
            lyricOffsets[trackID] = clamped
        }
        updateLyric()
        delegate?.persistLyricsChanges()
    }

    func search(title rawTitle: String, artist rawArtist: String) {
        guard !isShuttingDown else { return }
        guard let track = currentTrack else { return }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = rawArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            lyricsSearchMessage = AppLocalizer.string("请填写歌曲名")
            return
        }
        isSearchingLyrics = true
        lyricsSearchMessage = nil
        cancelLyricLoad()
        lyricsSearchTask?.cancel()
        lyricsSearchTask = Task { [weak self] in
            guard let self else { return }
            let found: LyricsDocument?
            do {
                found = try await lyricsService.search(
                    title: title,
                    artist: artist,
                    duration: track.duration
                )
            } catch is CancellationError {
                return
            } catch {
                guard !isShuttingDown, currentTrack?.id == track.id else { return }
                lyricsSearchMessage = error.localizedDescription
                isSearchingLyrics = false
                lyricsSearchTask = nil
                return
            }
            guard !isShuttingDown,
                  !Task.isCancelled,
                  currentTrack?.id == track.id else {
                return
            }
            if let found {
                lyrics = found
                cacheLyrics(found, for: track)
                updateMetadata(for: track.id, title: title, artist: artist)
                updateLyric()
                delegate?.persistLyricsChanges()
                lyricsSearchMessage = AppLocalizer.format(
                    "music.lyrics.matchResult",
                    title,
                    artist.isEmpty ? AppLocalizer.string("未知歌手") : artist
                )
            } else {
                lyricsSearchMessage = AppLocalizer.string(
                    "没有找到可信度足够的同步歌词，已保留原有歌词"
                )
            }
            isSearchingLyrics = false
            lyricsSearchTask = nil
        }
    }

    @discardableResult
    func updateCurrentTrackMetadata(title rawTitle: String, artist rawArtist: String) -> Bool {
        guard let track = currentTrack else { return false }
        let enteredTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredArtist = rawArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = enteredTitle.isEmpty ? track.title : enteredTitle
        let artist = enteredArtist.isEmpty ? track.artist : enteredArtist
        guard !title.isEmpty, !artist.isEmpty else {
            lyricsSearchMessage = AppLocalizer.string("歌曲名和歌手不能同时留空")
            return false
        }
        updateMetadata(for: track.id, title: title, artist: artist)
        lyricsSearchMessage = AppLocalizer.format("music.lyrics.metadataSaved", title, artist)
        return true
    }

    func updateMetadata(for trackID: String, title: String, artist: String) {
        let resolvedArtist = artist.isEmpty
            ? (currentTrack?.artist ?? AppLocalizer.string("未知歌手"))
            : artist
        delegate?.updateLyricsTrackMetadata(
            trackID: trackID,
            title: title,
            artist: resolvedArtist
        )
        delegate?.persistLyricsChanges()
    }

    static func encodeColor(_ color: NSColor) -> String {
        let color = color.usingColorSpace(.sRGB) ?? color
        return String(
            format: "#%02X%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255)),
            Int(round(color.alphaComponent * 255))
        )
    }

    static func decodeColor(_ value: String?) -> NSColor? {
        guard let value else { return nil }
        let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6 || hex.count == 8,
              let raw = UInt64(hex, radix: 16) else {
            return nil
        }
        let hasAlpha = hex.count == 8
        return NSColor(
            red: CGFloat((raw >> (hasAlpha ? 24 : 16)) & 0xFF) / 255,
            green: CGFloat((raw >> (hasAlpha ? 16 : 8)) & 0xFF) / 255,
            blue: CGFloat((raw >> (hasAlpha ? 8 : 0)) & 0xFF) / 255,
            alpha: hasAlpha ? CGFloat(raw & 0xFF) / 255 : 1
        )
    }

    func importLRC(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16) else {
            delegate?.reportLyricsError(AppLocalizer.string("无法读取这个 LRC 文件"))
            return
        }
        cancelLyricLoad()
        let document = LyricsParser.parseLRC(text)
        lyrics = document
        if let track = currentTrack {
            cacheLyrics(document, for: track)
            delegate?.persistLyricsChanges()
        }
        updateLyric()
    }
}
