enum DashboardMusicSourceAction: Equatable {
    case connectAppleMusic
    case selectBilibili

    static func resolve(_ source: MusicSource) -> Self {
        switch source {
        case .appleMusic: .connectAppleMusic
        case .bilibili: .selectBilibili
        }
    }
}
