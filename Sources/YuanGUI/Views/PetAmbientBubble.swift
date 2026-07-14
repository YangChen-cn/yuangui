import SwiftUI

struct PetAmbientBubble: View {
    @ObservedObject var store: PetStore

    var body: some View {
        HStack(alignment: .top, spacing: 10 * visualScale) {
            Image(systemName: icon)
                .font(.system(size: 18 * visualScale, weight: .bold))
                .foregroundStyle(.pink)
                .symbolEffect(.bounce, value: store.ambientMessage)
                .frame(width: 28 * visualScale, height: 28 * visualScale)
                .background(.pink.opacity(0.13), in: Circle())

            Text(store.ambientMessage ?? "")
                .font(.system(size: max(10, 12.5 * visualScale), weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { store.dismissAmbientMessage() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20 * visualScale, height: 20 * visualScale)
                    .background(.white.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)
            .help("收起这句话")
        }
        .padding(.horizontal, 13 * visualScale)
        .padding(.vertical, 11 * visualScale)
        .frame(width: PetLayout.ambientBubbleWidth(scale: store.petScale))
        .background(
            LinearGradient(
                colors: [.white.opacity(0.94), .pink.opacity(0.16), .blue.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22 * visualScale, style: .continuous)
        )
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22 * visualScale, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22 * visualScale).stroke(.white.opacity(0.82), lineWidth: 0.9))
        .shadow(color: .pink.opacity(0.18), radius: 14, y: 6)
        .overlay(alignment: .bottom) {
            PetBubbleTail()
                .fill(.regularMaterial)
                .frame(width: 20 * visualScale, height: 10 * visualScale)
                .offset(y: 8 * visualScale)
        }
    }

    private var visualScale: CGFloat {
        PetLayout.compactBubbleScale(scale: store.petScale)
    }

    private var icon: String {
        switch store.mode {
        case .yuanGui: return "heart.fill"
        case .vcc: return "pawprint.fill"
        case .duo: return "heart.circle.fill"
        }
    }
}
