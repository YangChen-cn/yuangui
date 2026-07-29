import AppKit
import Combine
import Foundation

extension BilibiliMusicCoordinator {
    func importBilibili() {
        let input = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isImporting = true
        errorMessage = nil
        dismissBilibiliImportResult()
        Task { [weak self] in
            guard let self else { return }
            do {
                let tracks = try await bilibili.resolveTracks(from: input)
                var added: [MusicTrack] = []
                for track in tracks where !playlist.contains(where: { $0.id == track.id }) {
                    playlist.append(track); added.append(track)
                }
                if !added.isEmpty {
                    playbackDomain.rebuildMusicPlaybackQueue()
                }
                importText = ""
                playbackDomain.setSource(.bilibili)
                libraryDomain.persistLibrary()
                let importedTrackID = (added.first ?? tracks.first)?.id
                let message = added.isEmpty
                    ? AppLocalizer.string("歌曲已在资料库中")
                    : AppLocalizer.format("music.import.addedCount", added.count)
                showBilibiliImportResult(message, trackID: importedTrackID)
            } catch { errorMessage = error.localizedDescription }
            isImporting = false
        }
    }

    func playLastBilibiliImport() {
        guard let lastImportedTrackID,
              let track = playlist.first(where: { $0.id == lastImportedTrackID }) else {
            dismissBilibiliImportResult()
            return
        }
        dismissBilibiliImportResult()
        playbackDomain.play(track)
    }

    func dismissBilibiliImportResult() {
        importResultTask?.cancel()
        importResultTask = nil
        bilibiliImportMessage = nil
        lastImportedTrackID = nil
    }

    func showBilibiliImportResult(_ message: String, trackID: String?) {
        importResultTask?.cancel()
        bilibiliImportMessage = message
        lastImportedTrackID = trackID
        importResultTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, bilibiliImportMessage == message, lastImportedTrackID == trackID else { return }
            dismissBilibiliImportResult()
        }
    }

    func loadBilibiliFavoriteFolders() {
        guard let account = bilibiliAccount else {
            bilibiliFavoriteMessage = AppLocalizer.string("请先登录哔哩哔哩账号")
            return
        }
        favoriteTask?.cancel()
        isLoadingBilibiliFavoriteFolders = true
        bilibiliFavoriteMessage = nil
        favoriteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let folders = try await favoritesService.folders(for: account.mid)
                guard !Task.isCancelled else { return }
                bilibiliFavoriteFolders = folders
                if folders.isEmpty {
                    bilibiliFavoriteMessage = AppLocalizer.string("这个账号没有可导入的视频收藏夹")
                }
            } catch is CancellationError {
                return
            } catch {
                bilibiliFavoriteMessage = error.localizedDescription
            }
            isLoadingBilibiliFavoriteFolders = false
            favoriteTask = nil
        }
    }

    func importBilibiliFavoriteFolder(_ folder: BilibiliFavoriteFolder) {
        guard bilibiliAccount != nil, !isImportingBilibiliFavoriteFolder else { return }
        favoriteTask?.cancel()
        isLoadingBilibiliFavoriteFolders = false
        isImportingBilibiliFavoriteFolder = true
        bilibiliFavoriteImportCompleted = 0
        bilibiliFavoriteImportTotal = max(folder.mediaCount, 0)
        bilibiliFavoriteMessage = nil
        favoriteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let bvids = try await favoritesService.videoBVIDs(in: folder)
                guard !bvids.isEmpty else {
                    bilibiliFavoriteMessage = AppLocalizer.format(
                        "music.bilibili.favorite.emptyFolder",
                        folder.title
                    )
                    isImportingBilibiliFavoriteFolder = false
                    favoriteTask = nil
                    return
                }
                bilibiliFavoriteImportTotal = bvids.count
                var resolved: [(Int, [MusicTrack])] = []
                var failedCount = 0
                let batchSize = 4
                let client = bilibili
                for start in stride(from: 0, to: bvids.count, by: batchSize) {
                    try Task.checkCancellation()
                    let end = min(start + batchSize, bvids.count)
                    let batch = Array(bvids[start..<end].enumerated()).map { (start + $0.offset, $0.element) }
                    let batchResults = await withTaskGroup(of: (Int, [MusicTrack]?).self) { group in
                        for (index, bvid) in batch {
                            group.addTask { [client] in
                                do { return (index, try await client.resolveTracks(from: bvid)) }
                                catch { return (index, nil) }
                            }
                        }
                        var values: [(Int, [MusicTrack]?)] = []
                        for await value in group { values.append(value) }
                        return values
                    }
                    for (index, tracks) in batchResults {
                        if let tracks { resolved.append((index, tracks)) }
                        else { failedCount += 1 }
                        bilibiliFavoriteImportCompleted += 1
                    }
                }
                guard !Task.isCancelled else { return }
                let tracks = resolved.sorted { $0.0 < $1.0 }.flatMap(\.1)
                let existingIDs = Set(playlist.map(\.id))
                let added = tracks.filter { !existingIDs.contains($0.id) }
                playlist.append(contentsOf: added)
                if !added.isEmpty {
                    playbackDomain.rebuildMusicPlaybackQueue()
                }
                updateLocalPlaylist(named: folder.title, with: tracks)
                playbackDomain.setSource(.bilibili)
                libraryDomain.persistLibrary()
                let duplicateCount = tracks.count - added.count
                bilibiliFavoriteMessage = AppLocalizer.format(
                    "music.bilibili.favorite.importResult",
                    folder.title,
                    added.count,
                    duplicateCount,
                    failedCount
                )
            } catch is CancellationError {
                return
            } catch {
                bilibiliFavoriteMessage = error.localizedDescription
            }
            isImportingBilibiliFavoriteFolder = false
            favoriteTask = nil
        }
    }

    func cancelBilibiliFavoriteOperation() {
        favoriteTask?.cancel()
        favoriteTask = nil
        isLoadingBilibiliFavoriteFolders = false
        isImportingBilibiliFavoriteFolder = false
    }

    func updateLocalPlaylist(named name: String, with tracks: [MusicTrack]) {
        guard !tracks.isEmpty else { return }
        if let index = savedPlaylists.firstIndex(where: { $0.name == name }) {
            var existing = Set(savedPlaylists[index].trackIDs)
            savedPlaylists[index].trackIDs.append(contentsOf: tracks.map(\.id).filter { existing.insert($0).inserted })
        } else {
            var seen = Set<String>()
            savedPlaylists.append(SavedMusicPlaylist(
                name: name,
                trackIDs: tracks.map(\.id).filter { seen.insert($0).inserted }
            ))
        }
    }

    func refreshBilibiliAccount() {
        Task { [weak self] in
            guard let self else { return }
            do {
                bilibiliAccount = try await accountService.currentAccount()
                bilibiliLoginPhase = bilibiliAccount == nil ? .loggedOut : .loggedIn
            } catch {
                bilibiliLoginPhase = .failed(error.localizedDescription)
            }
        }
    }

    func startBilibiliLogin() {
        loginTask?.cancel()
        bilibiliLoginPhase = .requestingQRCode
        bilibiliQRCodeURL = nil
        loginTask = Task { [weak self] in
            guard let self else { return }
            do {
                let code = try await accountService.generateQRCode()
                guard !Task.isCancelled else { return }
                bilibiliQRCodeURL = code.url
                bilibiliLoginPhase = .waitingForScan
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(2))
                    switch try await accountService.pollQRCode(key: code.key) {
                    case .waitingForScan:
                        bilibiliLoginPhase = .waitingForScan
                    case .waitingForConfirmation:
                        bilibiliLoginPhase = .waitingForConfirmation
                    case .expired:
                        bilibiliLoginPhase = .expired
                        bilibiliQRCodeURL = nil
                        loginTask = nil
                        return
                    case .succeeded:
                        guard let account = try await accountService.currentAccount() else {
                            throw BilibiliAccountError.api(AppLocalizer.string("登录凭据未生效"))
                        }
                        bilibiliAccount = account
                        bilibiliLoginPhase = .loggedIn
                        bilibiliQRCodeURL = nil
                        loginTask = nil
                        await context.lyricsCoordinator.refreshCurrentBilibiliSubtitleAfterLogin()
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                bilibiliLoginPhase = .failed(error.localizedDescription)
                bilibiliQRCodeURL = nil
                loginTask = nil
            }
        }
    }

    func cancelBilibiliLogin() {
        loginTask?.cancel()
        loginTask = nil
        bilibiliQRCodeURL = nil
        if bilibiliAccount == nil { bilibiliLoginPhase = .loggedOut }
    }

    func logoutBilibili() {
        loginTask?.cancel()
        loginTask = nil
        Task { [weak self] in
            guard let self else { return }
            await accountService.logout()
            bilibiliAccount = nil
            bilibiliQRCodeURL = nil
            bilibiliLoginPhase = .loggedOut
            bilibiliFavoriteFolders = []
            bilibiliFavoriteMessage = nil
        }
    }

}
