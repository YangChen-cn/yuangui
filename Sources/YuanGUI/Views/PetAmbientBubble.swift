import SwiftUI

struct PetAmbientBubble: View {
    @ObservedObject var store: PetStore

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.pink)
                .symbolEffect(.bounce, value: store.ambientMessage)
                .frame(width: 28, height: 28)
                .background(.pink.opacity(0.13), in: Circle())

            Text(store.ambientMessage ?? "")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { store.dismissAmbientMessage() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(.white.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain)
            .help("收起这句话")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(width: min(max(PetLayout.baseWidth * store.petScale - 54, 300), 370))
        .background(
            LinearGradient(
                colors: [.white.opacity(0.94), .pink.opacity(0.16), .blue.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.82), lineWidth: 0.9))
        .shadow(color: .pink.opacity(0.18), radius: 14, y: 6)
        .overlay(alignment: .bottom) {
            PetBubbleTail()
                .fill(.regularMaterial)
                .frame(width: 20, height: 10)
                .offset(y: 8)
        }
    }

    private var icon: String {
        switch store.mode {
        case .yuanGui: return "heart.fill"
        case .vcc: return "pawprint.fill"
        case .duo: return "heart.circle.fill"
        }
    }
}
