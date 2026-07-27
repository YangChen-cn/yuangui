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

            Text(AppLocalizer.string(store.ambientMessage ?? ""))
                .font(.system(size: max(10, 12.5 * visualScale), weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { store.dismissAmbientMessage() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 20 * visualScale, height: 20 * visualScale)
            }
            .yuanSystemGlassButton()
            .controlSize(.mini)
            .help(AppLocalizer.string("收起这句话"))
            .accessibilityLabel(AppLocalizer.string("收起这句话"))
        }
        .padding(.horizontal, 13 * visualScale)
        .padding(.vertical, 11 * visualScale)
        .frame(width: PetLayout.ambientBubbleWidth(scale: store.petScale))
        .yuanPetBubbleGlass(
            cornerRadius: 22 * visualScale,
            placement: placement,
            tailWidth: 20 * visualScale,
            tailHeight: 10 * visualScale,
            tailOffset: 8 * visualScale
        )
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
