import AVFoundation
import Foundation

struct LocalMusicMetadata: Sendable, Equatable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: TimeInterval
    let artworkData: Data?
}

protocol LocalMusicMetadataReading: Sendable {
    func read(at url: URL) async throws -> LocalMusicMetadata
}

struct AVFoundationLocalMusicMetadataReader: LocalMusicMetadataReading {
    func read(at url: URL) async throws -> LocalMusicMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let metadata = try await asset.load(.commonMetadata)
        var title: String?
        var artist: String?
        var album: String?
        var artwork: Data?
        for item in metadata {
            switch item.commonKey?.rawValue {
            case AVMetadataKey.commonKeyTitle.rawValue:
                title = try? await item.load(.stringValue)
            case AVMetadataKey.commonKeyArtist.rawValue:
                artist = try? await item.load(.stringValue)
            case AVMetadataKey.commonKeyAlbumName.rawValue:
                album = try? await item.load(.stringValue)
            case AVMetadataKey.commonKeyArtwork.rawValue:
                artwork = try? await item.load(.dataValue)
            default:
                break
            }
        }
        guard duration.isFinite, duration > 0 else { throw LocalMusicImportError.invalidTrack }
        return LocalMusicMetadata(
            title: title?.nilIfBlank,
            artist: artist?.nilIfBlank,
            album: album?.nilIfBlank,
            duration: duration,
            artworkData: artwork
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
