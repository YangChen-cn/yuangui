import SwiftUI

struct DashboardSectionPicker: View {
    @Binding var selection: DashboardSection

    @Environment(\.dashboardVisualTreatment) private var treatment
    @Namespace private var glassNamespace

    var body: some View {
        if treatment == .liquidGlass {
            if #available(macOS 26.0, *) {
                DashboardLiquidGlassSectionPicker(
                    selection: $selection,
                    glassNamespace: glassNamespace
                )
            } else {
                DashboardSegmentedSectionPicker(selection: $selection)
            }
        } else {
            DashboardSegmentedSectionPicker(selection: $selection)
        }
    }
}
