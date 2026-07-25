import SwiftUI

enum DashboardSurfaceProminence {
    case hero
    case card
    case subtle
}

struct DashboardSectionSurface<Content: View>: View {
    var prominence: DashboardSurfaceProminence = .card
    @ViewBuilder let content: Content

    @Environment(\.dashboardVisualTreatment) private var treatment

    var body: some View {
        content
            .padding(10)
            .background(
                treatment == .liquidGlass ? AnyShapeStyle(liquidSurfaceFill) : surfaceFill,
                in: .rect(cornerRadius: cornerRadius)
            )
    }

    private var surfaceFill: AnyShapeStyle {
        switch prominence {
        case .hero:
            AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.15),
                        Color.accentColor.opacity(0.055)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .card:
            AnyShapeStyle(Color.primary.opacity(0.045))
        case .subtle:
            AnyShapeStyle(Color.primary.opacity(0.022))
        }
    }

    private var cornerRadius: CGFloat {
        switch prominence {
        case .hero: DashboardDesign.heroRadius
        case .card, .subtle: DashboardDesign.sectionRadius
        }
    }

    private var liquidSurfaceFill: Color {
        switch prominence {
        case .hero:
            Color.accentColor.opacity(0.07)
        case .card:
            Color.primary.opacity(0.032)
        case .subtle:
            Color.primary.opacity(0.018)
        }
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

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .frame(minHeight: 30)
        }
        .dashboardSystemGlassButton(isProminent: isOn)
        .controlSize(.small)
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
