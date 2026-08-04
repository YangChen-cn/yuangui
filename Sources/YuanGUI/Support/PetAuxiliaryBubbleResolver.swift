import Foundation

/// What the auxiliary bubble is currently presenting. One resolved kind drives
/// rendering, window sizing and visibility so the view and the panel can never
/// disagree about which bubble is on screen.
enum PetAuxiliaryBubbleKind: Equatable {
    case maintenance
    case urgentStatus
    case guide
    case musicLyric
    case ambient
    case status
    case none
}

enum PetAuxiliaryBubbleResolver {
    /// Single source of truth for bubble precedence.
    /// Running maintenance task > truly urgent reminder > user-initiated guide
    /// > music lyric > ambient chatter > non-urgent smart status.
    /// A guide must not be covered by weather or casual chatter, but critical
    /// battery and severe memory pressure still outrank it.
    static func resolve(
        hasMaintenanceTask: Bool,
        urgentReminderVisible: Bool,
        activeGuide: PetGuide?,
        showsMusicLyric: Bool,
        ambientMessageVisible: Bool,
        showsStatusBubble: Bool
    ) -> PetAuxiliaryBubbleKind {
        if hasMaintenanceTask { return .maintenance }
        if urgentReminderVisible { return .urgentStatus }
        if activeGuide != nil { return .guide }
        if showsMusicLyric { return .musicLyric }
        if ambientMessageVisible { return .ambient }
        if showsStatusBubble { return .status }
        return .none
    }
}
