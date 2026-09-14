import SwiftUI

struct DashboardSectionPicker: View {
    @Binding var selection: DashboardSection

    @Environment(\.dashboardVisualTreatment) private var treatment
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if treatment == .liquidGlass && !reduceTransparency && contrast != .increased {
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
