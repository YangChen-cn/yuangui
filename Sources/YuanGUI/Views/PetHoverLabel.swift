import SwiftUI

struct PetHoverLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
            .allowsHitTesting(false)
    }
}
