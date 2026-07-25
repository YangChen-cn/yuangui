import SwiftUI

struct DashboardPetAvatarView: View {
    let mode: PetMode

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
                    .scaleEffect(1.28)
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: DashboardDesign.avatarSize, height: DashboardDesign.avatarSize)
        .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 13))
        .clipShape(.rect(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Color.accentColor.opacity(0.14))
        }
        .accessibilityLabel("\(mode.title)桌宠")
    }
}
