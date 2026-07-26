import SwiftUI

struct DashboardSectionPicker: View {
    @Binding var selection: DashboardSection

    @Environment(\.dashboardVisualTreatment) private var treatment

    var body: some View {
        if treatment == .liquidGlass {
            if #available(macOS 26.0, *) {
                DashboardLiquidGlassSectionPicker(selection: $selection)
            } else {
                DashboardSegmentedSectionPicker(selection: $selection)
            }
        } else {
            DashboardSegmentedSectionPicker(selection: $selection)
        }
    }
}
