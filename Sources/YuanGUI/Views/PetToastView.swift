import SwiftUI

struct PetToastView: View {
    let message: String
    let maximumWidth: CGFloat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            toastText
                .fixedSize(horizontal: true, vertical: true)

            toastText
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: max(maximumWidth - 26, 0))
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .accessibilityLabel(AppLocalizer.string(message))
    }

    private var toastText: some View {
        Text(AppLocalizer.string(message))
            .font(.system(size: 12, weight: .semibold, design: .rounded))
    }
}
