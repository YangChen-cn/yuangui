import SwiftUI

struct DashboardSectionPicker: View {
    @Binding var selection: DashboardSection

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(DashboardSection.allCases) { section in
                DashboardSectionButton(
                    section: section,
                    isSelected: selection == section,
                    select: { select(section) }
                )
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: DashboardDesign.controlRadius + 2))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("页面")
        .accessibilityValue(selection.title)
    }

    private func select(_ section: DashboardSection) {
        guard section != selection else { return }
        if reduceMotion {
            selection = section
        } else {
            withAnimation(.easeInOut(duration: DashboardDesign.animationDuration)) {
                selection = section
            }
        }
    }
}

private struct DashboardSectionButton: View {
    let section: DashboardSection
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(section.title, systemImage: section.systemImage, action: select)
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(backgroundColor, in: .rect(cornerRadius: DashboardDesign.controlRadius - 1))
            .contentShape(.rect)
            .onHover { isHovering = $0 }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityValue(isSelected ? "当前页" : "")
    }

    private var backgroundColor: Color {
        if isSelected { return Color.accentColor.opacity(0.14) }
        if isHovering { return Color.primary.opacity(0.05) }
        return .clear
    }
}
