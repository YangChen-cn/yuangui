import SwiftUI

struct DashboardGlassEffectGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    @Environment(\.dashboardVisualTreatment) private var treatment

    var body: some View {
        if treatment == .liquidGlass {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: spacing) {
                    content
                }
            } else {
                content
            }
        } else {
            content
        }
    }
}

extension View {
    func dashboardNavigationGlassSurface() -> some View {
        modifier(DashboardNavigationGlassSurfaceModifier())
    }

    func dashboardControlGlassSurface(
        isActive: Bool,
        isHovering: Bool,
        cornerRadius: CGFloat = DashboardDesign.controlRadius
    ) -> some View {
        modifier(
            DashboardControlGlassSurfaceModifier(
                isActive: isActive,
                isHovering: isHovering,
                cornerRadius: cornerRadius
            )
        )
    }

    func dashboardCapsuleGlassSurface(isActive: Bool) -> some View {
        modifier(DashboardCapsuleGlassSurfaceModifier(isActive: isActive))
    }
}

private struct DashboardNavigationGlassSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dashboardVisualTreatment) private var treatment

    @ViewBuilder
    func body(content: Content) -> some View {
        if treatment == .liquidGlass {
            if #available(macOS 26.0, *) {
                content.glassEffect(
                    .regular,
                    in: .rect(cornerRadius: DashboardDesign.controlRadius + 2)
                )
            } else {
                content.background {
                    fallbackSurface
                }
            }
        } else {
            content.background(
                Color.primary.opacity(0.035),
                in: .rect(cornerRadius: DashboardDesign.controlRadius + 2)
            )
        }
    }

    private var fallbackSurface: some View {
        let shape = RoundedRectangle(
            cornerRadius: DashboardDesign.controlRadius + 2,
            style: .continuous
        )
        return shape
            .fill(.thinMaterial)
            .overlay {
                shape.strokeBorder(
                    .white.opacity(colorScheme == .dark ? 0.18 : 0.52),
                    lineWidth: 0.55
                )
            }
    }
}

private struct DashboardControlGlassSurfaceModifier: ViewModifier {
    let isActive: Bool
    let isHovering: Bool
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dashboardVisualTreatment) private var treatment

    @ViewBuilder
    func body(content: Content) -> some View {
        if treatment == .liquidGlass {
            if #available(macOS 26.0, *) {
                content.glassEffect(
                    .regular
                        .tint(isActive ? Color.accentColor.opacity(0.18) : nil)
                        .interactive(),
                    in: .rect(cornerRadius: cornerRadius)
                )
            } else {
                content.background {
                    fallbackSurface
                }
            }
        } else {
            content.background(
                isActive
                    ? Color.accentColor.opacity(0.16)
                    : Color.primary.opacity(isHovering ? 0.08 : 0.035),
                in: .rect(cornerRadius: cornerRadius)
            )
        }
    }

    private var fallbackSurface: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return shape
            .fill(
                isActive
                    ? AnyShapeStyle(Color.accentColor.opacity(0.17))
                    : AnyShapeStyle(.thinMaterial)
            )
            .overlay {
                shape.strokeBorder(
                    .white.opacity(colorScheme == .dark ? 0.16 : 0.48),
                    lineWidth: 0.5
                )
            }
    }
}

private struct DashboardCapsuleGlassSurfaceModifier: ViewModifier {
    let isActive: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dashboardVisualTreatment) private var treatment

    @ViewBuilder
    func body(content: Content) -> some View {
        if treatment == .liquidGlass {
            if #available(macOS 26.0, *) {
                content.glassEffect(
                    .regular
                        .tint(isActive ? Color.accentColor.opacity(0.16) : nil)
                        .interactive(),
                    in: .capsule
                )
            } else {
                content.background {
                    fallbackSurface
                }
            }
        } else {
            content.background(
                isActive
                    ? Color.accentColor.opacity(0.12)
                    : Color.primary.opacity(0.035),
                in: .capsule
            )
        }
    }

    private var fallbackSurface: some View {
        Capsule()
            .fill(
                isActive
                    ? AnyShapeStyle(Color.accentColor.opacity(0.15))
                    : AnyShapeStyle(.thinMaterial)
            )
            .overlay {
                Capsule().strokeBorder(
                    .white.opacity(colorScheme == .dark ? 0.16 : 0.46),
                    lineWidth: 0.5
                )
            }
    }
}
