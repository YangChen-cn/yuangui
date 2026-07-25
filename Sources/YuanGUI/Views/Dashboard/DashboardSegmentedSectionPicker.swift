import SwiftUI

struct DashboardSegmentedSectionPicker: View {
    @Binding var selection: DashboardSection

    var body: some View {
        Picker("页面", selection: $selection) {
            ForEach(DashboardSection.allCases) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityValue(selection.title)
    }
}
