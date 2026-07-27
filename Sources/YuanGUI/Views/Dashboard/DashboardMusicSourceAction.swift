enum DashboardMusicSourceAction: Equatable {
    case connectAppleMusic
    case selectLocal
    case selectBilibili

    static func resolve(_ source: MusicSource) -> Self {
        switch source {
        case .appleMusic: .connectAppleMusic
        case .local: .selectLocal
        case .bilibili: .selectBilibili
        }
    }
}

enum DashboardMusicEmptyAction: CaseIterable, Equatable, Identifiable {
    case connectAppleMusic
    case importLocalMusic
    case openFullPlayer

    var id: Self { self }

    static func actions(for source: MusicSource) -> [Self] {
        switch source {
        case .appleMusic: [.connectAppleMusic, .openFullPlayer]
        case .local: [.importLocalMusic, .openFullPlayer]
        case .bilibili: [.openFullPlayer]
        }
    }

    var title: String {
        switch self {
        case .connectAppleMusic: AppLocalizer.string("连接 Apple Music")
        case .importLocalMusic: AppLocalizer.string("music.local.import.action")
        case .openFullPlayer: AppLocalizer.string("打开完整播放器")
        }
    }

    var systemImage: String? {
        switch self {
        case .connectAppleMusic: nil
        case .importLocalMusic: "plus"
        case .openFullPlayer: "arrow.up.right.square"
        }
    }
}
