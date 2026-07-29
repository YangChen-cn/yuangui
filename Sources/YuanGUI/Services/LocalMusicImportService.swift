import Foundation
import ImageIO

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
    case securityScopeUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: AppLocalizer.string("music.local.error.unsupported")
        case .missingFile: AppLocalizer.string("music.local.error.missing")
        case .staleBookmark: AppLocalizer.string("music.local.error.staleBookmark")
        case .invalidTrack: AppLocalizer.string("music.local.error.invalid")
        case .securityScopeUnavailable: AppLocalizer.string("music.local.error.securityScope")
        }
    }
}

enum MusicArtworkImportError: LocalizedError, Equatable {
    case invalidImage
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidImage: AppLocalizer.string("music.artwork.error.invalidImage")
        case .fileTooLarge: AppLocalizer.string("music.artwork.error.fileTooLarge")
        }
    }
}

protocol LocalMusicImporting: Sendable {
    func importFiles(_ urls: [URL]) async -> LocalMusicImportResult
    func resolveURL(for track: MusicTrack) async throws -> URL
    func relocatedTrack(_ track: MusicTrack, to url: URL) async throws -> MusicTrack
    func localLyrics(for track: MusicTrack) async throws -> LyricsDocument?
}

protocol LocalMusicArtworkManaging: Sendable {
    func store(_ data: Data, key: String) async throws
    func importArtwork(from url: URL) async throws -> String
    func data(for track: MusicTrack) async -> Data?
    func remove(keys: Set<String>) async
    func removeOrphans(keeping keys: Set<String>) async
}

actor LocalMusicArtworkRepository: LocalMusicArtworkManaging {
    static let shared = LocalMusicArtworkRepository()
    static let maximumArtworkBytes = 20 * 1_024 * 1_024
    static let maximumArtworkPixels: Int64 = 50_000_000

    private let rootURL: URL
    private let customRootURL: URL

    init(rootURL: URL? = nil, customRootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
            self.customRootURL = customRootURL ?? rootURL
        } else {
            self.rootURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appending(path: "YuanGUI/MusicArtwork", directoryHint: .isDirectory)
            self.customRootURL = customRootURL
                ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appending(path: "YuanGUI/CustomMusicArtwork", directoryHint: .isDirectory)
        }
    }

    func store(_ data: Data, key: String) throws {
        guard let destination = cacheURL(for: key) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: destination, options: .atomic)
    }

    func importArtwork(from url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw MusicArtworkImportError.invalidImage
        }
        if let fileSize = values.fileSize, fileSize > Self.maximumArtworkBytes {
            throw MusicArtworkImportError.fileTooLarge
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maximumArtworkBytes else {
            throw MusicArtworkImportError.fileTooLarge
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value,
              width > 0,
              height > 0,
              width <= Self.maximumArtworkPixels / height else {
            throw MusicArtworkImportError.invalidImage
        }
        let key = "custom-\(UUID().uuidString).artwork"
        try store(data, key: key)
        return key
    }

    func data(for track: MusicTrack) async -> Data? {
        guard let key = track.localArtworkCacheKey,
              let cacheURL = cacheURL(for: key) else { return nil }
        if let cached = try? Data(contentsOf: cacheURL) { return cached }
        guard track.source == .local else { return nil }
        guard let reference = track.local else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: reference.bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), !stale else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        guard accessed else { return nil }
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let artwork = try? await AVFoundationLocalMusicMetadataReader().read(at: url).artworkData else {
            return nil
        }
        try? store(artwork, key: key)
        return artwork
    }

    func remove(keys: Set<String>) {
        for key in keys {
            guard let url = cacheURL(for: key) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func removeOrphans(keeping keys: Set<String>) {
        for directory in Set([rootURL.standardizedFileURL, customRootURL.standardizedFileURL]) {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in contents where !keys.contains(url.lastPathComponent) {
                guard url.deletingLastPathComponent().standardizedFileURL == directory else {
                    continue
                }
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    continue
                }
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func cacheURL(for key: String) -> URL? {
        guard !key.isEmpty,
              key != ".",
              key != "..",
              URL(fileURLWithPath: key).lastPathComponent == key else { return nil }
        let directory = key.hasPrefix("custom-") ? customRootURL : rootURL
        let url = directory.appending(path: key).standardizedFileURL
        guard url.deletingLastPathComponent() == directory.standardizedFileURL else { return nil }
        return url
    }
}

actor LocalMusicImportService: LocalMusicImporting {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff"]

    private let artworkRepository: any LocalMusicArtworkManaging
    private let metadataReader: any LocalMusicMetadataReading
    private let maximumConcurrentMetadataReads: Int

    init(
        artworkRepository: any LocalMusicArtworkManaging = LocalMusicArtworkRepository.shared,
        metadataReader: any LocalMusicMetadataReading = AVFoundationLocalMusicMetadataReader(),
        maximumConcurrentMetadataReads: Int = 4
    ) {
        self.artworkRepository = artworkRepository
        self.metadataReader = metadataReader
        self.maximumConcurrentMetadataReads = max(1, maximumConcurrentMetadataReads)
    }

    func importFiles(_ urls: [URL]) async -> LocalMusicImportResult {
        let scopedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
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
                        group.addTask { [artworkRepository, metadataReader] in
                            do {
                                return (index, .success(try await Self.makeTrack(
                                    from: url,
                                    artworkRepository: artworkRepository,
                                    metadataReader: metadataReader
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
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: reference.bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            throw LocalMusicImportError.staleBookmark
        }
        guard !stale else { throw LocalMusicImportError.staleBookmark }
        guard FileManager.default.fileExists(atPath: url.path) else { throw LocalMusicImportError.missingFile }
        return url
    }

    func relocatedTrack(_ track: MusicTrack, to url: URL) async throws -> MusicTrack {
        guard track.source == .local else { throw LocalMusicImportError.invalidTrack }
        guard Self.isSupported(url) else { throw LocalMusicImportError.unsupportedFile }
        let accessed = url.startAccessingSecurityScopedResource()
        guard accessed else { throw LocalMusicImportError.securityScopeUnavailable }
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let metadata = try await metadataReader.read(at: url)
        var updated = track
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let artworkKey: String?
        if let artworkData = metadata.artworkData {
            let key = "\(UUID().uuidString).artwork"
            try await artworkRepository.store(artworkData, key: key)
            artworkKey = key
        } else {
            artworkKey = nil
        }
        updated.title = metadata.title ?? url.deletingPathExtension().lastPathComponent
        updated.artist = metadata.artist ?? AppLocalizer.string("music.local.unknownArtist")
        updated.album = metadata.album
        updated.duration = metadata.duration
        updated.local = LocalTrackReference(
            bookmarkData: bookmark,
            originalFilename: url.lastPathComponent,
            fileSize: values.fileSize.map(Int64.init)
        )
        updated.localArtworkCacheKey = artworkKey
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
        artworkRepository: any LocalMusicArtworkManaging,
        metadataReader: any LocalMusicMetadataReading
    ) async throws -> MusicTrack {
        try Task.checkCancellation()
        guard isSupported(url) else { throw LocalMusicImportError.unsupportedFile }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let metadata = try await metadataReader.read(at: url)
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
