import AppKit
import SwiftUI

struct PetToastView: View {
    private static let horizontalPadding: CGFloat = 13
    private static let textFontSize: CGFloat = 12

    let message: String
    let maximumWidth: CGFloat

    var body: some View {
        toastText
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(width: textWidth)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
            .accessibilityLabel(AppLocalizer.string(message))
    }

    private var toastText: some View {
        Text(AppLocalizer.string(message))
            .font(.system(size: Self.textFontSize, weight: .semibold, design: .rounded))
    }

    private var textWidth: CGFloat {
        max(
            Self.preferredWidth(for: message, maximumWidth: maximumWidth)
                - (Self.horizontalPadding * 2),
            0
        )
    }

    static func preferredWidth(for message: String, maximumWidth: CGFloat) -> CGFloat {
        let localizedMessage = AppLocalizer.string(message)
        let baseFont = NSFont.systemFont(ofSize: textFontSize, weight: .semibold)
        let font = baseFont.fontDescriptor
            .withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: textFontSize) }
            ?? baseFont
        let textSize = (localizedMessage as NSString).size(withAttributes: [.font: font])
        let intrinsicWidth = ceil(textSize.width) + (horizontalPadding * 2)
        return min(intrinsicWidth, max(maximumWidth, 0))
    }
}
