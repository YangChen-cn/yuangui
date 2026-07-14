import CoreGraphics

enum PetDockEdge: String, CaseIterable {
    case left
    case right
    case top
    case bottom
}

enum PetLayout {
    static let minimumScale = 0.70
    static let maximumScale = 1.40
    static let defaultScale = 0.85
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
    static let bottomToolbarButtonCount = 4
    static let bottomToolbarPanelPadding: CGFloat = 6
    static let bottomToolbarNormalBottomPadding: CGFloat = 6
    static let bottomToolbarChatBottomPadding: CGFloat = 70
    static var bottomToolbarPanelSize: CGSize {
        CGSize(
            width: bottomToolbarButtonWidth * CGFloat(bottomToolbarButtonCount)
                + bottomToolbarSpacing * CGFloat(bottomToolbarButtonCount - 1)
                + bottomToolbarPanelPadding * 2,
            height: 70
        )
    }
    static let edgePeekSize = CGSize(width: 76, height: 76)
    static let edgePeekStatusSize = CGSize(width: 194, height: 76)
    static let edgePeekInset: CGFloat = 3

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

    static func petVisualFrame(panelFrame: CGRect, scale: Double, showsChat: Bool) -> CGRect {
        let petSize = 326 * scale
        return CGRect(
            x: panelFrame.minX + (panelFrame.width - petSize) / 2 + 35 * scale,
            y: panelFrame.minY + (showsChat ? 58 : 0),
            width: petSize,
            height: petSize
        )
    }

    static func dockingEdge(for petVisualFrame: CGRect, in visibleFrame: CGRect) -> PetDockEdge? {
        let outsideDistances: [(PetDockEdge, CGFloat)] = [
            (.left, visibleFrame.minX - petVisualFrame.midX),
            (.right, petVisualFrame.midX - visibleFrame.maxX),
            (.top, petVisualFrame.midY - visibleFrame.maxY),
            (.bottom, visibleFrame.minY - petVisualFrame.midY)
        ]
        return outsideDistances
            .filter { $0.1 >= 0 }
            .max { $0.1 < $1.1 }?
            .0
    }

    static func constrainedOrigin(
        _ proposed: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect,
        allowedTopOverflow: CGFloat
    ) -> CGPoint {
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - panelSize.height + allowedTopOverflow)
        return CGPoint(
            x: min(max(proposed.x, visibleFrame.minX), maximumX),
            y: min(max(proposed.y, visibleFrame.minY), maximumY)
        )
    }

    static func edgePeekPanelSize(showsMiniStatus: Bool) -> CGSize {
        showsMiniStatus ? edgePeekStatusSize : edgePeekSize
    }

    static func edgePeekOrigin(
        edge: PetDockEdge,
        anchorFrame: CGRect,
        visibleFrame: CGRect,
        peekSize size: CGSize = edgePeekSize
    ) -> CGPoint {
        let centeredX = min(
            max(anchorFrame.midX - size.width / 2, visibleFrame.minX + edgePeekInset),
            visibleFrame.maxX - size.width - edgePeekInset
        )
        let centeredY = min(
            max(anchorFrame.midY - size.height / 2, visibleFrame.minY + edgePeekInset),
            visibleFrame.maxY - size.height - edgePeekInset
        )
        switch edge {
        case .left:
            return CGPoint(x: visibleFrame.minX + edgePeekInset, y: centeredY)
        case .right:
            return CGPoint(x: visibleFrame.maxX - size.width - edgePeekInset, y: centeredY)
        case .top:
            return CGPoint(x: centeredX, y: visibleFrame.maxY - size.height - edgePeekInset)
        case .bottom:
            return CGPoint(x: centeredX, y: visibleFrame.minY + edgePeekInset)
        }
    }

    static func tuckedOrigin(edge: PetDockEdge, panelSize: CGSize, visibleFrame: CGRect, anchorOrigin: CGPoint) -> CGPoint {
        switch edge {
        case .left:
            return CGPoint(x: visibleFrame.minX - panelSize.width + edgePeekSize.width / 2, y: anchorOrigin.y)
        case .right:
            return CGPoint(x: visibleFrame.maxX - edgePeekSize.width / 2, y: anchorOrigin.y)
        case .top:
            return CGPoint(x: anchorOrigin.x, y: visibleFrame.maxY - edgePeekSize.height / 2)
        case .bottom:
            return CGPoint(x: anchorOrigin.x, y: visibleFrame.minY - panelSize.height + edgePeekSize.height / 2)
        }
    }

    static func expandedOrigin(
        edge: PetDockEdge,
        previousOrigin: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect,
        allowedTopOverflow: CGFloat
    ) -> CGPoint {
        var proposed = previousOrigin
        switch edge {
        case .left:
            proposed.x = visibleFrame.minX + 8
        case .right:
            proposed.x = visibleFrame.maxX - panelSize.width - 8
        case .top:
            proposed.y = visibleFrame.maxY - panelSize.height + allowedTopOverflow - 8
        case .bottom:
            proposed.y = visibleFrame.minY + 8
        }
        return constrainedOrigin(
            proposed,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            allowedTopOverflow: allowedTopOverflow
        )
    }
}
