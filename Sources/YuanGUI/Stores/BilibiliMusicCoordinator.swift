import Foundation

@MainActor
final class BilibiliMusicCoordinator: MusicDomainCoordinator {
    let bilibili: any BilibiliMusicProviding
    let accountService: BilibiliAccountService
    let favoritesService: BilibiliFavoritesService

    var importResultTask: Task<Void, Never>?
    var loginTask: Task<Void, Never>?
    var favoriteTask: Task<Void, Never>?
    var lastImportedTrackID: String?

    init(
        context: MusicFeatureContext,
        bilibili: any BilibiliMusicProviding,
        accountService: BilibiliAccountService = BilibiliAccountService(),
        favoritesService: BilibiliFavoritesService = BilibiliFavoritesService()
    ) {
        self.bilibili = bilibili
        self.accountService = accountService
        self.favoritesService = favoritesService
        super.init(context: context)
    }

    func start() {
        refreshBilibiliAccount()
    }

    func shutdown() {
        importResultTask?.cancel()
        importResultTask = nil
        loginTask?.cancel()
        loginTask = nil
        favoriteTask?.cancel()
        favoriteTask = nil
    }
}
