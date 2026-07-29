import AppKit
import Combine
import Foundation

extension LocalMusicCoordinator {
    func importLocalMusic(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        importTask?.cancel()
        localImportStore.isImporting = true
        localImportStore.message = nil
        localImportStore.errorMessage = nil
        localImportStore.failures = []
        importTask = Task(priority: .utility) { [weak self, importer] in
            let result = await importer.importFiles(urls)
            guard !Task.isCancelled, let self else { return }
            let existingKeys = Set(playlist.compactMap(\.localDuplicateKey))
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
            playlist.append(contentsOf: added)
            localImportStore.importedCount = added.count
            localImportStore.duplicateCount = duplicates
            localImportStore.failedCount = result.failures.count
            localImportStore.failures = result.failures
            localImportStore.message = AppLocalizer.format(
                "music.local.import.result",
                added.count,
                duplicates,
                result.failures.count
            )
            localImportStore.isImporting = false
            importTask = nil
            scheduleArtworkRemoval(
                keys: orphanedArtworkKeys(
                    among: Set(duplicateTracks.compactMap(\.localArtworkCacheKey))
                )
            )
            if !added.isEmpty {
                context.playbackCoordinator.setSource(.local)
                if currentTrack?.source != .local {
                    context.playbackCoordinator.restoreSelection(for: .local)
                }
                context.playbackCoordinator.rebuildMusicPlaybackQueue()
                context.libraryController.persistLibrary()
            }
        }
    }

    func cancelLocalImport() {
        importTask?.cancel()
        importTask = nil
        localImportStore.isImporting = false
    }

    func relocate(_ track: MusicTrack, to url: URL) {
        Task { [weak self, importer] in
            guard let self else { return }
            do {
                let updated = try await importer.relocatedTrack(track, to: url)
                guard let index = playlist.firstIndex(where: { $0.id == track.id }) else {
                    scheduleArtworkRemoval(keys: Set([updated.localArtworkCacheKey].compactMap { $0 }))
                    return
                }
                playlist[index] = updated
                context.lyricsCoordinator.removeCachedLyrics(for: track)
                if currentTrack?.id == track.id {
                    context.playbackCoordinator.urlPlayer?.stop()
                    context.playbackCoordinator.clearLoadedURLIdentity()
                    context.playbackCoordinator.releaseScopedLocalURL()
                    currentTrack = updated
                    playbackProgress.setDuration(updated.duration)
                    playbackProgress.setPosition(min(position, updated.duration))
                    context.playbackCoordinator.setPlaybackState(.paused)
                    context.lyricsCoordinator.loadLyrics(for: updated)
                }
                localImportStore.trackNeedingRelocation = nil
                localImportStore.errorMessage = nil
                if let oldKey = track.localArtworkCacheKey, oldKey != updated.localArtworkCacheKey {
                    scheduleArtworkRemoval(keys: orphanedArtworkKeys(among: [oldKey]))
                }
                context.libraryController.persistLibrary()
            } catch {
                localImportStore.errorMessage = error.localizedDescription
            }
        }
    }

    func revealInFinder(_ track: MusicTrack) {
        guard track.source == .local else { return }
        Task { [weak self, importer] in
            guard let self else { return }
            do {
                let url = try await importer.resolveURL(for: track)
                let accessed = url.startAccessingSecurityScopedResource()
                guard accessed else { throw LocalMusicImportError.securityScopeUnavailable }
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                fileRevealer.reveal(url)
                localImportStore.errorMessage = nil
            } catch {
                localImportStore.errorMessage = error.localizedDescription
                if error as? LocalMusicImportError == .staleBookmark
                    || error as? LocalMusicImportError == .missingFile {
                    localImportStore.trackNeedingRelocation = track
                }
            }
        }
    }

    func setArtwork(for track: MusicTrack, from imageURL: URL) {
        guard track.source != .appleMusic else { return }
        Task { [weak self, artworkRepository] in
            guard let self else { return }
            do {
                let newKey = try await artworkRepository.importArtwork(from: imageURL)
                guard let index = playlist.firstIndex(where: { $0.id == track.id }) else {
                    scheduleArtworkRemoval(keys: [newKey])
                    return
                }
                let oldKey = playlist[index].localArtworkCacheKey
                playlist[index].localArtworkCacheKey = newKey
                let updated = playlist[index]
                if currentTrack?.id == updated.id {
                    currentTrack = updated
                }
                localImportStore.errorMessage = nil
                context.libraryController.persistLibrary()
                if let oldKey, oldKey != newKey {
                    scheduleArtworkRemoval(keys: orphanedArtworkKeys(among: [oldKey]))
                }
            } catch {
                localImportStore.errorMessage = error.localizedDescription
            }
        }
    }

    func removeArtwork(for track: MusicTrack) {
        guard track.source != .appleMusic,
              let index = playlist.firstIndex(where: { $0.id == track.id }),
              let oldKey = playlist[index].localArtworkCacheKey else { return }
        playlist[index].localArtworkCacheKey = nil
        let updated = playlist[index]
        if currentTrack?.id == updated.id {
            currentTrack = updated
        }
        localImportStore.errorMessage = nil
        context.libraryController.persistLibrary()
        scheduleArtworkRemoval(keys: orphanedArtworkKeys(among: [oldKey]))
    }

}
