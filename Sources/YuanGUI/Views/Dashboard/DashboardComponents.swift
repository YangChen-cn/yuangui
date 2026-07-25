import SwiftUI

struct DashboardSectionSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(10)
            .background(.primary.opacity(0.045), in: .rect(cornerRadius: DashboardDesign.sectionRadius))
    }
}

struct DashboardStatusLabel: View {
    let presentation: DashboardSmartStatePresentation

    var body: some View {
        Label(presentation.title, systemImage: presentation.systemImage)
            .font(.caption)
            .foregroundStyle(presentation.severity.color)
            .labelStyle(.titleAndIcon)
            .accessibilityElement(children: .combine)
    }
}

struct DashboardToggleButton: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(width: 32, height: 30)
            .background(
                isOn ? Color.accentColor.opacity(0.16) : Color.primary.opacity(isHovering ? 0.08 : 0.035),
                in: .rect(cornerRadius: DashboardDesign.controlRadius)
            )
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 7))
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    .padding(3)
            }
            .onHover { isHovering = $0 }
            .help("\(title)：\(isOn ? "开" : "关")")
            .accessibilityValue(isOn ? "开" : "关")
    }
}

struct DashboardEmptyState: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .controlSize(.small)
    }
}
