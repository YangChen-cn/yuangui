import SwiftUI

extension View {
    func dashboardSystemGlassButton(isProminent: Bool = false) -> some View {
        modifier(DashboardSystemGlassButtonStyleModifier(isProminent: isProminent))
    }
}

private struct DashboardSystemGlassButtonStyleModifier: ViewModifier {
    let isProminent: Bool

    @Environment(\.dashboardVisualTreatment) private var treatment

    @ViewBuilder
    func body(content: Content) -> some View {
        if treatment == .liquidGlass {
            if #available(macOS 26.0, *) {
                content.yuanSystemGlassButton(isProminent: isProminent)
            } else {
                fallbackStyle(content: content)
            }
        } else {
            fallbackStyle(content: content)
        }
    }

    @ViewBuilder
    private func fallbackStyle(content: Content) -> some View {
        if isProminent {
            content
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
