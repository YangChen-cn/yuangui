import SwiftUI

struct DashboardSectionPicker: View {
    @Binding var selection: DashboardSection

    var body: some View {
        Picker("面板页面", selection: $selection) {
            ForEach(DashboardSection.allCases) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
                    .accessibilityLabel("\(section.title)\(selection == section ? "，当前页" : "")")
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityValue(selection.title)
    }
}
