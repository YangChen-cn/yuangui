import AppKit
import Combine
import Foundation

extension BilibiliMusicCoordinator {
    func importBilibili() {
        guard !tasks.isShuttingDown else { return }
        let requestInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestInput.isEmpty else { return }
        isImporting = true
        errorMessage = nil
        dismissBilibiliImportResult()
        tasks.launch(key: "import") { [weak self, bilibili] generation in
            guard let self else { return }
            do {
                let tracks = try await bilibili.resolveTracks(from: requestInput)
                guard tasks.isCurrent(generation) else { return }
                let added = delegate?.importBilibiliTracks(tracks, playlistName: nil) ?? []
                input = ""
                let importedTrackID = (added.first ?? tracks.first)?.id
                let message = added.isEmpty
                    ? AppLocalizer.string("歌曲已在资料库中")
                    : AppLocalizer.format("music.import.addedCount", added.count)
                showBilibiliImportResult(message, trackID: importedTrackID)
            } catch {
                guard tasks.isCurrent(generation) else { return }
                errorMessage = error.localizedDescription
            }
            guard tasks.isCurrent(generation) else { return }
            isImporting = false
        }
    }

    func playLastBilibiliImport() {
        guard let lastImportedTrackID,
              let track = delegate?.bilibiliTrack(withID: lastImportedTrackID) else {
            dismissBilibiliImportResult()
            return
        }
        dismissBilibiliImportResult()
        delegate?.playBilibiliTrack(track)
    }

    func dismissBilibiliImportResult() {
        tasks.cancel(key: "import-result")
        importMessage = nil
        lastImportedTrackID = nil
    }

    func showBilibiliImportResult(_ message: String, trackID: String?) {
        guard !tasks.isShuttingDown else { return }
        importMessage = message
        lastImportedTrackID = trackID
        tasks.launch(key: "import-result") { [weak self] generation in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self,
                  tasks.isCurrent(generation),
                  importMessage == message,
                  lastImportedTrackID == trackID else {
                return
            }
            dismissBilibiliImportResult()
        }
    }

    func loadBilibiliFavoriteFolders() {
        guard !tasks.isShuttingDown else { return }
        guard let account else {
            favoriteMessage = AppLocalizer.string("请先登录哔哩哔哩账号")
            return
        }
        isLoadingFavoriteFolders = true
        favoriteMessage = nil
        tasks.launch(key: "favorite-operation") { [weak self, favoritesService] generation in
            guard let self else { return }
            do {
                let folders = try await favoritesService.folders(for: account.mid)
                guard tasks.isCurrent(generation) else { return }
                favoriteFolders = folders
                if folders.isEmpty {
                    favoriteMessage = AppLocalizer.string("这个账号没有可导入的视频收藏夹")
                }
            } catch is CancellationError {
                return
            } catch {
                guard tasks.isCurrent(generation) else { return }
                favoriteMessage = error.localizedDescription
            }
            guard tasks.isCurrent(generation) else { return }
            isLoadingFavoriteFolders = false
        }
    }

    func importBilibiliFavoriteFolder(_ folder: BilibiliFavoriteFolder) {
        guard !tasks.isShuttingDown else { return }
        guard account != nil, !isImportingFavoriteFolder else { return }
        isLoadingFavoriteFolders = false
        isImportingFavoriteFolder = true
        favoriteImportCompleted = 0
        favoriteImportTotal = max(folder.mediaCount, 0)
        favoriteMessage = nil
        tasks.launch(key: "favorite-operation") {
            [weak self, favoritesService, bilibili] generation in
            guard let self else { return }
            do {
                let bvids = try await favoritesService.videoBVIDs(in: folder)
                guard tasks.isCurrent(generation) else { return }
                guard !bvids.isEmpty else {
                    favoriteMessage = AppLocalizer.format(
                        "music.bilibili.favorite.emptyFolder",
                        folder.title
                    )
                    isImportingFavoriteFolder = false
                    return
                }
                favoriteImportTotal = bvids.count
                var resolved: [(Int, [MusicTrack])] = []
                var failedCount = 0
                let batchSize = 4
                for start in stride(from: 0, to: bvids.count, by: batchSize) {
                    guard tasks.isCurrent(generation) else { return }
                    let end = min(start + batchSize, bvids.count)
                    let batch = Array(bvids[start..<end].enumerated()).map { (start + $0.offset, $0.element) }
                    let batchResults = await withTaskGroup(of: (Int, [MusicTrack]?).self) { group in
                        for (index, bvid) in batch {
                            group.addTask { [bilibili] in
                                do { return (index, try await bilibili.resolveTracks(from: bvid)) }
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
                        favoriteImportCompleted += 1
                    }
                }
                guard tasks.isCurrent(generation) else { return }
                let tracks = resolved.sorted { $0.0 < $1.0 }.flatMap(\.1)
                let added = delegate?.importBilibiliTracks(
                    tracks,
                    playlistName: folder.title
                ) ?? []
                let duplicateCount = tracks.count - added.count
                favoriteMessage = AppLocalizer.format(
                    "music.bilibili.favorite.importResult",
                    folder.title,
                    added.count,
                    duplicateCount,
                    failedCount
                )
            } catch is CancellationError {
                return
            } catch {
                guard tasks.isCurrent(generation) else { return }
                favoriteMessage = error.localizedDescription
            }
            guard tasks.isCurrent(generation) else { return }
            isImportingFavoriteFolder = false
        }
    }

    func cancelBilibiliFavoriteOperation() {
        tasks.cancel(key: "favorite-operation")
        isLoadingFavoriteFolders = false
        isImportingFavoriteFolder = false
    }

    func refreshBilibiliAccount() {
        guard !tasks.isShuttingDown else { return }
        tasks.launch(key: "account-refresh") { [weak self, accountService] generation in
            guard let self else { return }
            do {
                let refreshedAccount = try await accountService.currentAccount()
                guard tasks.isCurrent(generation) else { return }
                account = refreshedAccount
                loginPhase = refreshedAccount == nil ? .loggedOut : .loggedIn
            } catch {
                guard tasks.isCurrent(generation) else { return }
                loginPhase = .failed(error.localizedDescription)
            }
        }
    }

    func startBilibiliLogin() {
        guard !tasks.isShuttingDown else { return }
        loginPhase = .requestingQRCode
        qrCodeURL = nil
        tasks.launch(key: "login") { [weak self, accountService] generation in
            guard let self else { return }
            do {
                let code = try await accountService.generateQRCode()
                guard tasks.isCurrent(generation) else { return }
                qrCodeURL = code.url
                loginPhase = .waitingForScan
                while tasks.isCurrent(generation) {
                    try await Task.sleep(for: .seconds(2))
                    switch try await accountService.pollQRCode(key: code.key) {
                    case .waitingForScan:
                        loginPhase = .waitingForScan
                    case .waitingForConfirmation:
                        loginPhase = .waitingForConfirmation
                    case .expired:
                        loginPhase = .expired
                        qrCodeURL = nil
                        return
                    case .succeeded:
                        guard let account = try await accountService.currentAccount() else {
                            throw BilibiliAccountError.api(AppLocalizer.string("登录凭据未生效"))
                        }
                        guard tasks.isCurrent(generation) else { return }
                        self.account = account
                        loginPhase = .loggedIn
                        qrCodeURL = nil
                        await delegate?.refreshCurrentBilibiliLyricsAfterLogin()
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard tasks.isCurrent(generation) else { return }
                loginPhase = .failed(error.localizedDescription)
                qrCodeURL = nil
            }
        }
    }

    func cancelBilibiliLogin() {
        tasks.cancel(key: "login")
        qrCodeURL = nil
        if account == nil { loginPhase = .loggedOut }
    }

    func logoutBilibili() {
        guard !tasks.isShuttingDown else { return }
        tasks.cancel(key: "login")
        tasks.launch(key: "logout") { [weak self, accountService] generation in
            guard let self else { return }
            await accountService.logout()
            guard tasks.isCurrent(generation) else { return }
            account = nil
            qrCodeURL = nil
            loginPhase = .loggedOut
            favoriteFolders = []
            favoriteMessage = nil
        }
    }

}
