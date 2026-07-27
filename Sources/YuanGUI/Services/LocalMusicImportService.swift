import AVFoundation
import Foundation

struct LocalMusicImportFailure: Sendable, Equatable {
    let filename: String
    let message: String
}

struct LocalMusicImportResult: Sendable, Equatable {
    var tracks: [MusicTrack]
    var failures: [LocalMusicImportFailure]
}

enum LocalMusicImportError: LocalizedError, Equatable {
    case unsupportedFile
    case missingFile
    case staleBookmark
    case invalidTrack

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: AppLocalizer.string("music.local.error.unsupported")
        case .missingFile: AppLocalizer.string("music.local.error.missing")
        case .staleBookmark: AppLocalizer.string("music.local.error.staleBookmark")
        case .invalidTrack: AppLocalizer.string("music.local.error.invalid")
        }
    }
}

protocol LocalMusicImporting: Sendable {
    func importFiles(_ urls: [URL]) async -> LocalMusicImportResult
    func resolveURL(for track: MusicTrack) async throws -> URL
    func relocatedTrack(_ track: MusicTrack, to url: URL) async throws -> MusicTrack
    func localLyrics(for track: MusicTrack) async throws -> LyricsDocument?
}

actor LocalMusicArtworkRepository {
    static let shared = LocalMusicArtworkRepository()

    private let rootURL: URL

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "YuanGUI/MusicArtwork", directoryHint: .isDirectory)
    }

    func store(_ data: Data, key: String) throws {
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: rootURL.appending(path: key), options: .atomic)
    }

    func data(for track: MusicTrack) async -> Data? {
        guard track.source == .local, let key = track.localArtworkCacheKey else { return nil }
        let cacheURL = rootURL.appending(path: key)
        if let cached = try? Data(contentsOf: cacheURL) { return cached }
        guard let reference = track.local else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: reference.bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), !stale else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let artwork = await LocalMusicMetadataReader.artworkData(at: url) else { return nil }
        try? store(artwork, key: key)
        return artwork
    }
}

actor LocalMusicImportService: LocalMusicImporting {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff"]

    private let artworkRepository: LocalMusicArtworkRepository
    private let maximumConcurrentMetadataReads: Int

    init(
        artworkRepository: LocalMusicArtworkRepository = .shared,
        maximumConcurrentMetadataReads: Int = 4
    ) {
        self.artworkRepository = artworkRepository
        self.maximumConcurrentMetadataReads = max(1, maximumConcurrentMetadataReads)
    }

    func importFiles(_ urls: [URL]) async -> LocalMusicImportResult {
        do {
            let files = try collectAudioFiles(from: urls)
            var tracks: [(Int, MusicTrack)] = []
            var failures: [(Int, LocalMusicImportFailure)] = []

            for batchStart in stride(from: 0, to: files.count, by: maximumConcurrentMetadataReads) {
                if Task.isCancelled { break }
                let end = min(batchStart + maximumConcurrentMetadataReads, files.count)
                let batch = Array(files[batchStart..<end].enumerated()).map {
                    (batchStart + $0.offset, $0.element)
                }
                await withTaskGroup(of: (Int, Result<MusicTrack, Error>).self) { group in
                    for (index, url) in batch {
                        group.addTask { [artworkRepository] in
                            do {
                                return (index, .success(try await Self.makeTrack(
                                    from: url,
                                    artworkRepository: artworkRepository
                                )))
                            } catch {
                                return (index, .failure(error))
                            }
                        }
                    }
                    for await (index, result) in group {
                        switch result {
                        case .success(let track): tracks.append((index, track))
                        case .failure(let error):
                            failures.append((index, LocalMusicImportFailure(
                                filename: files[index].lastPathComponent,
                                message: error.localizedDescription
                            )))
                        }
                    }
                }
            }

            return LocalMusicImportResult(
                tracks: tracks.sorted { $0.0 < $1.0 }.map(\.1),
                failures: failures.sorted { $0.0 < $1.0 }.map(\.1)
            )
        } catch is CancellationError {
            return LocalMusicImportResult(tracks: [], failures: [])
        } catch {
            return LocalMusicImportResult(
                tracks: [],
                failures: urls.map {
                    LocalMusicImportFailure(filename: $0.lastPathComponent, message: error.localizedDescription)
                }
            )
        }
    }

    func resolveURL(for track: MusicTrack) throws -> URL {
        guard let reference = track.local else { throw LocalMusicImportError.invalidTrack }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: reference.bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        guard !stale else { throw LocalMusicImportError.staleBookmark }
        guard FileManager.default.fileExists(atPath: url.path) else { throw LocalMusicImportError.missingFile }
        return url
    }

    func relocatedTrack(_ track: MusicTrack, to url: URL) async throws -> MusicTrack {
        guard track.source == .local else { throw LocalMusicImportError.invalidTrack }
        guard Self.isSupported(url) else { throw LocalMusicImportError.unsupportedFile }
        var updated = track
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        updated.local = LocalTrackReference(
            bookmarkData: try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ),
            originalFilename: url.lastPathComponent,
            fileSize: values.fileSize.map(Int64.init)
        )
        return updated
    }

    func localLyrics(for track: MusicTrack) async throws -> LyricsDocument? {
        let url = try resolveURL(for: track)
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
        guard FileManager.default.fileExists(atPath: lrcURL.path) else { return nil }
        let data = try Data(contentsOf: lrcURL)
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16) else {
            throw LocalMusicImportError.invalidTrack
        }
        return LyricsParser.parseLRC(text, source: AppLocalizer.string("music.lyrics.localFile"))
    }

    private func collectAudioFiles(from urls: [URL]) throws -> [URL] {
        var files: [URL] = []
        var seen = Set<String>()
        for url in urls {
            try Task.checkCancellation()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true {
                let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
                guard let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                while let child = enumerator.nextObject() as? URL {
                    try Task.checkCancellation()
                    if Self.isSupported(child), seen.insert(child.standardizedFileURL.path).inserted {
                        files.append(child)
                    }
                }
            } else if Self.isSupported(url), seen.insert(url.standardizedFileURL.path).inserted {
                files.append(url)
            }
        }
        return files
    }

    private static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private static func makeTrack(
        from url: URL,
        artworkRepository: LocalMusicArtworkRepository
    ) async throws -> MusicTrack {
        try Task.checkCancellation()
        guard isSupported(url) else { throw LocalMusicImportError.unsupportedFile }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let metadata = try await LocalMusicMetadataReader.read(at: url)
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let id = UUID()
        let artworkKey = "\(id.uuidString).artwork"
        if let artwork = metadata.artworkData {
            try? await artworkRepository.store(artwork, key: artworkKey)
        }
        return MusicTrack(
            id: "local:\(id.uuidString)",
            source: .local,
            title: metadata.title ?? url.deletingPathExtension().lastPathComponent,
            artist: metadata.artist ?? AppLocalizer.string("music.local.unknownArtist"),
            album: metadata.album,
            coverURL: nil,
            duration: metadata.duration,
            bilibili: nil,
            subtitleURL: nil,
            local: LocalTrackReference(
                bookmarkData: try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ),
                originalFilename: url.lastPathComponent,
                fileSize: values.fileSize.map(Int64.init)
            ),
            localArtworkCacheKey: metadata.artworkData == nil ? nil : artworkKey
        )
    }
}

private struct LocalMusicMetadata: Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: TimeInterval
    let artworkData: Data?
}

private enum LocalMusicMetadataReader {
    static func read(at url: URL) async throws -> LocalMusicMetadata {
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

    static func artworkData(at url: URL) async -> Data? {
        try? await read(at: url).artworkData
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
