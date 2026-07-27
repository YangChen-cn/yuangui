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
