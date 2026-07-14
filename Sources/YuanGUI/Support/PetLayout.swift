import CoreGraphics

enum PetLayout {
    static let minimumScale = 0.70
    static let maximumScale = 1.40
    static let baseWidth: CGFloat = 390
    static let basePetHeight: CGFloat = 390
    static let bubbleHeight: CGFloat = 24

    static func panelSize(scale: Double, showsBubble: Bool) -> CGSize {
        CGSize(
            width: baseWidth * scale,
            height: basePetHeight * scale + (showsBubble ? bubbleHeight : 0)
        )
    }
}
