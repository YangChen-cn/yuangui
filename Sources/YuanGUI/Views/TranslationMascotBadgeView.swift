import SwiftUI

struct TranslationMascotBadgeView: View {
    let mode: PetMode
    let accent: Color
    var size: CGFloat = 26

    private var image: NSImage? {
        guard let action = mode.actions.first else { return nil }
        return SpriteLoader.image(mode: mode, action: action)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(1.25)
            } else {
                Image(systemName: mode == .vcc ? "pawprint.fill" : "person.fill")
                    .foregroundStyle(accent)
            }
        }
        .frame(width: size, height: size)
        .background(accent.opacity(0.12), in: .rect(cornerRadius: size * 0.3))
        .clipShape(.rect(cornerRadius: size * 0.3))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.3)
                .strokeBorder(accent.opacity(0.18), lineWidth: 0.7)
        }
        .accessibilityHidden(true)
    }
}
