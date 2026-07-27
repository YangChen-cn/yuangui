import SwiftUI

enum DashboardSurfaceProminence: Equatable {
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
            .modifier(
                DashboardSectionSurfaceModifier(
                    treatment: treatment,
                    prominence: prominence,
                    surfaceFill: surfaceFill,
                    liquidSurfaceFill: liquidSurfaceFill,
                    cornerRadius: cornerRadius
                )
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
            Color.accentColor.opacity(0.04)
        case .card:
            Color.primary.opacity(0.032)
        case .subtle:
            Color.primary.opacity(0.018)
        }
    }
}

private struct DashboardSectionSurfaceModifier: ViewModifier {
    let treatment: DashboardVisualTreatment
    let prominence: DashboardSurfaceProminence
    let surfaceFill: AnyShapeStyle
    let liquidSurfaceFill: Color
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if treatment == .liquidGlass, prominence == .hero {
            content.background(
                liquidSurfaceFill,
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            content.background(
                treatment == .liquidGlass ? AnyShapeStyle(liquidSurfaceFill) : surfaceFill,
                in: .rect(cornerRadius: cornerRadius)
            )
        }
    }
}

struct DashboardStatusLabel: View {
    let presentation: DashboardSmartStatePresentation

    var body: some View {
            Label(AppLocalizer.string(presentation.title), systemImage: presentation.systemImage)
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
            Label(AppLocalizer.string(title), systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(minHeight: 30)
        }
        .dashboardSystemGlassButton()
        .controlSize(.small)
        .help("\(AppLocalizer.string(title)): \(isOn ? AppLocalizer.string("开") : AppLocalizer.string("关"))")
        .accessibilityValue(isOn ? AppLocalizer.string("开") : AppLocalizer.string("关"))
    }
}

struct DashboardEmptyState: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ContentUnavailableView(
            AppLocalizer.string(title),
            systemImage: systemImage,
            description: Text(AppLocalizer.string(description))
        )
        .controlSize(.small)
    }
}
