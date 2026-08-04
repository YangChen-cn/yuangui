import SwiftUI

/// Onboarding / feature-tip bubble: message plus primary and secondary
/// buttons rendered with native SwiftUI button styles.
struct PetGuideBubbleView: View {
    @ObservedObject var guide: PetGuideCoordinator
    var placement: PetAuxiliaryBubblePlacement = .abovePet
    var petScale: Double

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9 * visualScale) {
            HStack(alignment: .top, spacing: 10 * visualScale) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17 * visualScale, weight: .bold))
                    .foregroundStyle(.pink)
                    .frame(width: 28 * visualScale, height: 28 * visualScale)
                    .background(.pink.opacity(0.13), in: Circle())

                Text(guide.currentGuide?.message ?? "")
                    .font(.system(size: max(10, 12.5 * visualScale), weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button { guide.dismissCurrentGuide() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20 * visualScale, height: 20 * visualScale)
                }
                .yuanSystemGlassButton()
                .controlSize(.mini)
                .help(AppLocalizer.string("收起这句话"))
                .accessibilityLabel(AppLocalizer.string("收起这句话"))
            }

            if let current = guide.currentGuide {
                HStack(spacing: 8 * visualScale) {
                    if let secondaryTitle = current.secondaryTitle {
                        Button(secondaryTitle) { guide.performSecondaryAction() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    if let primaryTitle = current.primaryTitle {
                        Button(primaryTitle) { guide.performPrimaryAction() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 38 * visualScale)
            }
        }
        .padding(.horizontal, 13 * visualScale)
        .padding(.vertical, 11 * visualScale)
        .frame(width: PetLayout.guideBubbleWidth(scale: petScale))
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
        PetLayout.compactBubbleScale(scale: petScale)
    }
}
