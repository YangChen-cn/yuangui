import SwiftUI

struct DashboardSectionPicker: View {
    @Binding var selection: DashboardSection

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
        .dashboardNavigationGlassSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("页面")
        .accessibilityValue(selection.title)
    }

    private func select(_ section: DashboardSection) {
        guard section != selection else { return }
        selection = section
    }
}

private struct DashboardSectionButton: View {
    let section: DashboardSection
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            Label(section.title, systemImage: section.systemImage)
                .font(.callout)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(backgroundColor, in: .rect(cornerRadius: DashboardDesign.controlRadius - 1))
                .contentShape(.rect)
        }
            .buttonStyle(.plain)
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
