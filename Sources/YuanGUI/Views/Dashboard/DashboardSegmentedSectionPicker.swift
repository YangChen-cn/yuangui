import SwiftUI

struct DashboardSegmentedSectionPicker: View {
    @Binding var selection: DashboardSection

    var body: some View {
        HStack(spacing: 3) {
            ForEach(DashboardSection.allCases) { section in
                Button { selection = section } label: {
                    Label(section.title, systemImage: section.systemImage)
                        .font(.callout.weight(selection == section ? .semibold : .regular))
                        .foregroundStyle(selection == section ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: DashboardDesign.navigationHeight - 4)
                        .background(selection == section ? Color.accentColor.opacity(0.18) : .clear,
                                    in: .rect(cornerRadius: DashboardDesign.controlRadius))
                }
                .buttonStyle(DashboardPressButtonStyle())
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("页面")
        .accessibilityValue(selection.title)
    }
}
