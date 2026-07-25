import SwiftUI

@MainActor
final class DashboardPanelState: ObservableObject {
    @Published var selectedSection: DashboardSection = .overview
}
