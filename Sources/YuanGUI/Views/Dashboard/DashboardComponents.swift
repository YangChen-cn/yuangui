import SwiftUI

enum DashboardSurfaceProminence {
    case hero
    case card
    case subtle
}

struct DashboardSectionSurface<Content: View>: View {
    var prominence: DashboardSurfaceProminence = .card
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(10)
            .background(surfaceFill, in: .rect(cornerRadius: cornerRadius))
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
}

struct DashboardAtmosphereBackground: View {
    let palette: DashboardPalette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
            LinearGradient(
                colors: [
                    palette.topGlow.opacity(palette.ambientOpacity),
                    .clear,
                    palette.bottomGlow.opacity(palette.ambientOpacity * 0.75)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(palette.topGlow.opacity(palette.ambientOpacity * 0.7))
                .frame(width: 170, height: 170)
                .blur(radius: 46)
                .offset(x: -135, y: -215)
            Circle()
                .fill(palette.bottomGlow.opacity(palette.ambientOpacity * 0.55))
                .frame(width: 150, height: 150)
                .blur(radius: 52)
                .offset(x: 150, y: 230)
        }
        .clipShape(.rect(cornerRadius: 20))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .padding(.horizontal, 9)
                .frame(minHeight: 30)
                .background(
                    isOn ? Color.accentColor.opacity(0.16) : Color.primary.opacity(isHovering ? 0.08 : 0.035),
                    in: .rect(cornerRadius: DashboardDesign.controlRadius)
                )
                .contentShape(.rect)
        }
            .buttonStyle(.plain)
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
