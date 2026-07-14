import CoreGraphics

enum PetLayout {
    static let minimumScale = 0.70
    static let maximumScale = 1.40
    static let baseWidth: CGFloat = 390
    static let basePetHeight: CGFloat = 390
    static let bubbleHeight: CGFloat = 116
    static let chatHeight: CGFloat = 214
    static let minimumBubbleWidth: CGFloat = 360
    static let minimumChatWidth: CGFloat = 450

    static func panelSize(scale: Double, showsBubble: Bool, showsChat: Bool = false) -> CGSize {
        let scaledWidth = baseWidth * scale
        return CGSize(
            width: showsChat ? max(scaledWidth, minimumChatWidth) :
                (showsBubble ? max(scaledWidth, minimumBubbleWidth) : scaledWidth),
            height: basePetHeight * scale + (showsChat ? chatHeight : (showsBubble ? bubbleHeight : 0))
        )
    }
}
