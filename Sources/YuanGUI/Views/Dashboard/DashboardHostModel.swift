import SwiftUI

@MainActor
final class DashboardHostModel: ObservableObject {
    @Published var width: CGFloat
    @Published var maximumHeight: CGFloat
    @Published var isPresented = false

    init(
        width: CGFloat = DashboardDesign.preferredWidth,
        maximumHeight: CGFloat = DashboardDesign.expandedHeight
    ) {
        self.width = width
        self.maximumHeight = maximumHeight
    }
}
