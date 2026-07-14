import CoreGraphics

enum PetLayout {
    static let minimumScale = 0.70
    static let maximumScale = 1.40
    static let baseWidth: CGFloat = 540
    static let basePetHeight: CGFloat = 390
    static let bubbleHeight: CGFloat = 116
    static let chatHeight: CGFloat = 214
    static let maintenanceHeight: CGFloat = 255
    static let minimumBubbleWidth: CGFloat = 360
    static let minimumChatWidth: CGFloat = 450
    static let compactTopTransparentInset: CGFloat = 58
    static let bottomToolbarButtonWidth: CGFloat = 32
    static let bottomToolbarSpacing: CGFloat = 5
    static let bottomToolbarButtonCount = 6
    static let bottomToolbarLockIndex = 4
    static let bottomToolbarPanelPadding: CGFloat = 6
    static let bottomToolbarNormalBottomPadding: CGFloat = 6
    static let bottomToolbarChatBottomPadding: CGFloat = 70

    static func panelSize(scale: Double, showsBubble: Bool, showsChat: Bool = false, showsMaintenance: Bool = false) -> CGSize {
        let scaledWidth = baseWidth * scale
        let auxiliaryHeight = showsMaintenance ? maintenanceHeight : (showsChat ? chatHeight : (showsBubble ? bubbleHeight : 0))
        return CGSize(
            width: (showsChat || showsMaintenance) ? max(scaledWidth, minimumChatWidth) :
                (showsBubble ? max(scaledWidth, minimumBubbleWidth) : scaledWidth),
            height: basePetHeight * scale + auxiliaryHeight
        )
    }

    static func allowedTopOverflow(scale: Double, showsBubble: Bool, showsChat: Bool, showsMaintenance: Bool) -> CGFloat {
        guard !showsBubble, !showsChat, !showsMaintenance else { return 0 }
        return compactTopTransparentInset * scale
    }

    static func bottomLockCenter(panelWidth: CGFloat, showsChat: Bool) -> CGPoint {
        let buttonsWidth = bottomToolbarButtonWidth * CGFloat(bottomToolbarButtonCount)
        let spacesWidth = bottomToolbarSpacing * CGFloat(bottomToolbarButtonCount - 1)
        let rowWidth = buttonsWidth + spacesWidth
        let leading = (panelWidth - rowWidth) / 2
        let lockX = leading + CGFloat(bottomToolbarLockIndex) * (bottomToolbarButtonWidth + bottomToolbarSpacing) + bottomToolbarButtonWidth / 2
        let bottom = showsChat ? bottomToolbarChatBottomPadding : bottomToolbarNormalBottomPadding
        let lockY = bottom + bottomToolbarPanelPadding + 14
        return CGPoint(x: lockX, y: lockY)
    }
}
