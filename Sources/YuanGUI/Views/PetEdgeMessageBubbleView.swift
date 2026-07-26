import SwiftUI

struct PetEdgeMessageBubbleView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(
                width: PetLayout.edgeMessageSize.width,
                height: PetLayout.edgeMessageSize.height,
                alignment: .leading
            )
            .yuanLiquidGlassSurface(.clear, cornerRadius: 16)
            .accessibilityHidden(true)
    }
}
