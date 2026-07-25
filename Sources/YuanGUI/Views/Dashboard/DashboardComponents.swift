import SwiftUI

enum DashboardSurfaceProminence {
    case hero
    case card
    case subtle
}

struct DashboardSectionSurface<Content: View>: View {
    var prominence: DashboardSurfaceProminence = .card
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dashboardVisualTreatment) private var treatment

    var body: some View {
        content
            .padding(10)
            .background {
                surfaceBackground
            }
    }

    @ViewBuilder
    private var surfaceBackground: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if treatment == .liquidGlass {
            shape
                .fill(liquidSurfaceFill)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.20 : 0.62),
                                .white.opacity(0.04),
                                Color.primary.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.6
                    )
                }
        } else {
            shape.fill(surfaceFill)
        }
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
            Color.accentColor.opacity(colorScheme == .dark ? 0.10 : 0.07)
        case .card:
            Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.028)
        case .subtle:
            Color.primary.opacity(colorScheme == .dark ? 0.025 : 0.014)
        }
    }
}

struct DashboardAtmosphereBackground: View {
    let palette: DashboardPalette

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
            if palette.treatment == .liquidGlass {
                liquidGlassAtmosphere
            } else {
                ambientGlow
            }
        }
        .clipShape(.rect(cornerRadius: 20))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var ambientGlow: some View {
        ZStack {
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
    }

    private var liquidGlassAtmosphere: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(colorScheme == .dark ? 0.08 : 0.20),
                        palette.bottomGlow.opacity(palette.ambientOpacity),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.35 : 0.72),
                                .white.opacity(0.08),
                                palette.bottomGlow.opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
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

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .padding(.horizontal, 9)
                .frame(minHeight: 30)
                .dashboardControlGlassSurface(
                    isActive: isOn,
                    isHovering: isHovering
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
