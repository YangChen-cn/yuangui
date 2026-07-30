import AppKit
import Combine
import Foundation

extension LocalMusicCoordinator {
    func importLocalMusic(_ urls: [URL]) {
        guard !tasks.isShuttingDown, !urls.isEmpty else { return }
        importStore.isImporting = true
        importStore.message = nil
        importStore.errorMessage = nil
        importStore.failures = []
        tasks.launch(key: "import") {
            [weak self, importer, artworkRepository] generation in
            let result = await importer.importFiles(urls)
            guard let self else {
                await artworkRepository.remove(
                    keys: Set(result.tracks.compactMap(\.localArtworkCacheKey))
                )
                return
            }
            guard tasks.isCurrent(generation) else {
                await artworkRepository.remove(
                    keys: Set(result.tracks.compactMap(\.localArtworkCacheKey))
                )
                return
            }
            let existingKeys = delegate?.localDuplicateKeys ?? []
            var seen = existingKeys
            var added: [MusicTrack] = []
            var duplicateTracks: [MusicTrack] = []
            for track in result.tracks {
                guard let key = track.localDuplicateKey else {
                    added.append(track)
                    continue
                }
                if seen.insert(key).inserted {
                    added.append(track)
                } else {
                    duplicateTracks.append(track)
                }
            }
            let duplicates = duplicateTracks.count
            delegate?.appendImportedLocalTracks(added)
            importStore.importedCount = added.count
            importStore.duplicateCount = duplicates
            importStore.failedCount = result.failures.count
            importStore.failures = result.failures
            importStore.message = AppLocalizer.format(
                "music.local.import.result",
                added.count,
                duplicates,
                result.failures.count
            )
            importStore.isImporting = false
            scheduleArtworkRemoval(
                keys: orphanedArtworkKeys(
                    among: Set(duplicateTracks.compactMap(\.localArtworkCacheKey))
                )
            )
            if !added.isEmpty {
                delegate?.didImportLocalTracks()
            }
        }
    }

    func cancelLocalImport() {
        tasks.cancel(key: "import")
        importStore.isImporting = false
    }

    func relocate(_ track: MusicTrack, to url: URL) {
        guard !tasks.isShuttingDown else { return }
        tasks.launch(key: "relocate:\(track.id)") {
            [weak self, importer, artworkRepository] generation in
            do {
                let updated = try await importer.relocatedTrack(track, to: url)
                let generatedArtworkKeys = Set(
                    [updated.localArtworkCacheKey].compactMap { $0 }
                ).subtracting(Set([track.localArtworkCacheKey].compactMap { $0 }))
                guard let self else {
                    await artworkRepository.remove(keys: generatedArtworkKeys)
                    return
                }
                guard tasks.isCurrent(generation) else {
                    await artworkRepository.remove(keys: generatedArtworkKeys)
                    return
                }
                guard delegate?.replaceLocalTrack(track, with: updated) == true else {
                    await artworkRepository.remove(keys: generatedArtworkKeys)
                    return
                }
                delegate?.didRelocateCurrentLocalTrack(track, to: updated)
                importStore.trackNeedingRelocation = nil
                importStore.errorMessage = nil
                if let oldKey = track.localArtworkCacheKey, oldKey != updated.localArtworkCacheKey {
                    scheduleArtworkRemoval(keys: orphanedArtworkKeys(among: [oldKey]))
                }
                delegate?.persistLocalMusicChanges()
            } catch {
                guard let self, self.tasks.isCurrent(generation) else { return }
                self.importStore.errorMessage = error.localizedDescription
            }
        }
    }

    func revealInFinder(_ track: MusicTrack) {
        guard !tasks.isShuttingDown, track.source == .local else { return }
        tasks.launch(key: "reveal:\(track.id)") {
            [weak self, importer, fileRevealer] generation in
            guard let self else { return }
            do {
                let url = try await importer.resolveURL(for: track)
                guard tasks.isCurrent(generation) else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                guard accessed else { throw LocalMusicImportError.securityScopeUnavailable }
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                fileRevealer.reveal(url)
                importStore.errorMessage = nil
            } catch {
                guard tasks.isCurrent(generation) else { return }
                importStore.errorMessage = error.localizedDescription
                if error as? LocalMusicImportError == .staleBookmark
                    || error as? LocalMusicImportError == .missingFile {
                    importStore.trackNeedingRelocation = track
                }
            }
        }
    }

    func setArtwork(for track: MusicTrack, from imageURL: URL) {
        guard !tasks.isShuttingDown, track.source != .appleMusic else { return }
        tasks.launch(key: "artwork-import:\(track.id)") {
            [weak self, artworkRepository] generation in
            guard let self else { return }
            do {
                let newKey = try await artworkRepository.importArtwork(from: imageURL)
                guard tasks.isCurrent(generation) else {
                    await artworkRepository.remove(keys: [newKey])
                    return
                }
                let replacement = delegate?.replaceArtwork(
                    for: track.id,
                    with: newKey
                )
                guard replacement?.didReplace == true else {
                    await artworkRepository.remove(keys: [newKey])
                    return
                }
                importStore.errorMessage = nil
                delegate?.persistLocalMusicChanges()
                if let oldKey = replacement?.previousKey, oldKey != newKey {
                    scheduleArtworkRemoval(keys: orphanedArtworkKeys(among: [oldKey]))
                }
            } catch {
                guard tasks.isCurrent(generation) else { return }
                importStore.errorMessage = error.localizedDescription
            }
        }
    }

    func removeArtwork(for track: MusicTrack) {
        guard track.source != .appleMusic,
              let oldKey = delegate?.removeArtwork(for: track.id) else {
            return
        }
        importStore.errorMessage = nil
        delegate?.persistLocalMusicChanges()
        scheduleArtworkRemoval(keys: orphanedArtworkKeys(among: [oldKey]))
    }

}
