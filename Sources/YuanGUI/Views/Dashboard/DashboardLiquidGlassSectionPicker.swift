import SwiftUI

@available(macOS 26.0, *)
struct DashboardLiquidGlassSectionPicker: View {
    @Binding var selection: DashboardSection

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

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
            .frame(height: DashboardDesign.navigationHeight)
        }
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
            if isSelected {
                Label(section.title, systemImage: section.systemImage)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: DashboardDesign.navigationHeight - 4)
                    .contentShape(.rect(cornerRadius: DashboardDesign.controlRadius - 1))
                    .glassEffect(
                        .regular
                            .tint(Color.accentColor.opacity(0.06))
                            .interactive(),
                        in: .rect(cornerRadius: DashboardDesign.controlRadius - 1)
                    )
                    .glassEffectID(section.id, in: glassNamespace)
            } else {
                Label(section.title, systemImage: section.systemImage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: DashboardDesign.navigationHeight - 4)
                    .background(
                        Color.primary.opacity(isHovering ? 0.035 : 0),
                        in: .rect(cornerRadius: DashboardDesign.controlRadius - 1)
                    )
                    .contentShape(.rect(cornerRadius: DashboardDesign.controlRadius - 1))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "当前页" : "")
    }
}
