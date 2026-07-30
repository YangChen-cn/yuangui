import Foundation

@MainActor
protocol BilibiliMusicCoordinatorDelegate: AnyObject {
    func importBilibiliTracks(
        _ tracks: [MusicTrack],
        playlistName: String?
    ) -> [MusicTrack]
    func bilibiliTrack(withID id: String) -> MusicTrack?
    func playBilibiliTrack(_ track: MusicTrack)
    func refreshCurrentBilibiliLyricsAfterLogin() async
}

@MainActor
final class BilibiliMusicCoordinator {
    weak var delegate: (any BilibiliMusicCoordinatorDelegate)?

    let accountStore: BilibiliAccountStore
    let importStore: BilibiliImportStore
    let bilibili: any BilibiliMusicProviding
    let accountService: BilibiliAccountService
    let favoritesService: BilibiliFavoritesService
    let tasks = MusicTaskRegistry()

    var lastImportedTrackID: String?

    init(
        accountStore: BilibiliAccountStore,
        importStore: BilibiliImportStore,
        bilibili: any BilibiliMusicProviding,
        accountService: BilibiliAccountService = BilibiliAccountService(),
        favoritesService: BilibiliFavoritesService = BilibiliFavoritesService()
    ) {
        self.accountStore = accountStore
        self.importStore = importStore
        self.bilibili = bilibili
        self.accountService = accountService
        self.favoritesService = favoritesService
    }

    func start() {
        refreshBilibiliAccount()
    }

    func shutdown() async {
        await tasks.shutdown()
        isImporting = false
        isLoadingFavoriteFolders = false
        isImportingFavoriteFolder = false
        qrCodeURL = nil
    }

    var account: BilibiliAccount? {
        get { accountStore.account }
        set { accountStore.account = newValue }
    }
    var loginPhase: BilibiliLoginPhase {
        get { accountStore.loginPhase }
        set { accountStore.loginPhase = newValue }
    }
    var qrCodeURL: String? {
        get { accountStore.qrCodeURL }
        set { accountStore.qrCodeURL = newValue }
    }
    var input: String {
        get { importStore.input }
        set { importStore.input = newValue }
    }
    var isImporting: Bool {
        get { importStore.isImporting }
        set { importStore.isImporting = newValue }
    }
    var importMessage: String? {
        get { importStore.importMessage }
        set { importStore.importMessage = newValue }
    }
    var errorMessage: String? {
        get { importStore.errorMessage }
        set { importStore.errorMessage = newValue }
    }
    var favoriteFolders: [BilibiliFavoriteFolder] {
        get { importStore.favoriteFolders }
        set { importStore.favoriteFolders = newValue }
    }
    var isLoadingFavoriteFolders: Bool {
        get { importStore.isLoadingFavoriteFolders }
        set { importStore.isLoadingFavoriteFolders = newValue }
    }
    var isImportingFavoriteFolder: Bool {
        get { importStore.isImportingFavoriteFolder }
        set { importStore.isImportingFavoriteFolder = newValue }
    }
    var favoriteImportCompleted: Int {
        get { importStore.completedCount }
        set { importStore.completedCount = newValue }
    }
    var favoriteImportTotal: Int {
        get { importStore.totalCount }
        set { importStore.totalCount = newValue }
    }
    var favoriteMessage: String? {
        get { importStore.favoriteMessage }
        set { importStore.favoriteMessage = newValue }
    }
}
