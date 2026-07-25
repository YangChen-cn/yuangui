import SwiftUI

@available(macOS 26.0, *)
struct DashboardLiquidGlassSectionPicker: View {
    @Binding var selection: DashboardSection
    let glassNamespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: DashboardDesign.compactSpacing) {
            HStack(spacing: 3) {
                ForEach(DashboardSection.allCases) { section in
                    DashboardLiquidGlassSectionButton(
                        section: section,
                        isSelected: selection == section,
                        glassNamespace: glassNamespace,
                        select: { select(section) }
                    )
                }
            }
        }
        .padding(3)
        .background(
            Color.primary.opacity(0.025),
            in: .rect(cornerRadius: DashboardDesign.controlRadius + 2)
        )
        .animation(
            reduceMotion ? nil : .snappy(duration: DashboardDesign.navigationAnimationDuration),
            value: selection
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("页面")
        .accessibilityValue(selection.title)
    }

    private func select(_ section: DashboardSection) {
        guard section != selection else { return }
        withAnimation(
            reduceMotion ? nil : .snappy(duration: DashboardDesign.navigationAnimationDuration)
        ) {
            selection = section
        }
    }
}

@available(macOS 26.0, *)
private struct DashboardLiquidGlassSectionButton: View {
    let section: DashboardSection
    let isSelected: Bool
    let glassNamespace: Namespace.ID
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: DashboardDesign.controlRadius - 1)
                        .fill(.clear)
                        .glassEffect(
                            .regular
                                .tint(Color.accentColor.opacity(0.10))
                                .interactive(),
                            in: .rect(cornerRadius: DashboardDesign.controlRadius - 1)
                        )
                        .glassEffectID("dashboard-section-selection", in: glassNamespace)
                        .glassEffectTransition(.matchedGeometry)
                } else if isHovering {
                    RoundedRectangle(cornerRadius: DashboardDesign.controlRadius - 1)
                        .fill(Color.primary.opacity(0.045))
                }

                Label(section.title, systemImage: section.systemImage)
                    .font(.callout)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "当前页" : "")
    }
}
