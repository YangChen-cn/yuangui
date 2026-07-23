import SwiftUI

struct PetAmbientBubble: View {
    @ObservedObject var store: PetStore
    var placement: PetAuxiliaryBubblePlacement = .abovePet
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 10 * visualScale) {
            Image(systemName: icon)
                .font(.system(size: 18 * visualScale, weight: .bold))
                .foregroundStyle(.pink)
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
            Color(nsColor: .windowBackgroundColor).opacity(0.96),
            in: RoundedRectangle(cornerRadius: 22 * visualScale, style: .continuous)
        )
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 22 * visualScale, style: .continuous))
        .background(
            LinearGradient(
                colors: [.pink.opacity(0.12), .blue.opacity(0.07), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22 * visualScale, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 22 * visualScale).stroke(.white.opacity(0.58), lineWidth: 0.9))
        .shadow(color: .black.opacity(0.12), radius: 7, y: 3)
        .overlay(alignment: placement == .abovePet ? .bottom : .top) {
            PetBubbleTail()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                .frame(width: 20 * visualScale, height: 10 * visualScale)
                .rotationEffect(.degrees(placement == .abovePet ? 0 : 180))
                .offset(y: (placement == .abovePet ? 8 : -8) * visualScale)
        }
        .opacity(appeared ? 1 : 0.9)
        .offset(y: appeared ? 0 : -4)
        .onAppear {
            withAnimation(.easeOut(duration: 0.14)) { appeared = true }
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
