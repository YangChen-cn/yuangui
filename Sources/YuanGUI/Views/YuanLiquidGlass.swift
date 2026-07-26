import SwiftUI

enum YuanLiquidGlassVariant {
    case regular
    case clear
}

extension View {
    /// A single native Liquid Glass surface on macOS 26, with a restrained
    /// material fallback for the app's macOS 15 deployment target.
    func yuanLiquidGlassSurface(
        _ variant: YuanLiquidGlassVariant = .regular,
        cornerRadius: CGFloat
    ) -> some View {
        modifier(
            YuanLiquidGlassSurfaceModifier(
                variant: variant,
                cornerRadius: cornerRadius
            )
        )
    }

    /// Native glass button chrome. Neutral controls explicitly clear inherited
    /// tint so their foreground remains readable over bright desktop content.
    func yuanSystemGlassButton(isProminent: Bool = false) -> some View {
        modifier(YuanSystemGlassButtonModifier(isProminent: isProminent))
    }

    func yuanGlassEffectContainer(spacing: CGFloat) -> some View {
        modifier(YuanGlassEffectContainerModifier(spacing: spacing))
    }

    /// Speech bubbles sit directly over rich desktop content, where Apple's
    /// clear glass variant is appropriate. The tail participates in the same
    /// glass container so it visually joins the main surface.
    func yuanPetBubbleGlass(
        cornerRadius: CGFloat,
        placement: PetAuxiliaryBubblePlacement,
        tailWidth: CGFloat,
        tailHeight: CGFloat,
        tailOffset: CGFloat
    ) -> some View {
        modifier(
            YuanPetBubbleGlassModifier(
                cornerRadius: cornerRadius,
                placement: placement,
                tailWidth: tailWidth,
                tailHeight: tailHeight,
                tailOffset: tailOffset
            )
        )
    }
}

private struct YuanGlassEffectContainerModifier: ViewModifier {
    let spacing: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

private struct YuanLiquidGlassSurfaceModifier: ViewModifier {
    let variant: YuanLiquidGlassVariant
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            switch variant {
            case .regular:
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            case .clear:
                content.glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.6)
                }
                .shadow(color: .black.opacity(0.12), radius: 9, y: 4)
        }
    }
}

private struct YuanSystemGlassButtonModifier: ViewModifier {
    let isProminent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if isProminent {
                content
                    .buttonStyle(.glassProminent)
                    .tint(.accentColor)
            } else {
                content
                    .buttonStyle(.glass)
                    .tint(nil)
                    .foregroundStyle(.primary)
            }
        } else if isProminent {
            content
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct YuanPetBubbleGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let placement: PetAuxiliaryBubblePlacement
    let tailWidth: CGFloat
    let tailHeight: CGFloat
    let tailOffset: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                content
                    .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
                    .overlay(alignment: placement == .abovePet ? .bottom : .top) {
                        PetBubbleTail()
                            .fill(Color.clear)
                            .frame(width: tailWidth, height: tailHeight)
                            .glassEffect(.clear, in: PetBubbleTail())
                            .rotationEffect(.degrees(placement == .abovePet ? 0 : 180))
                            .offset(y: placement == .abovePet ? tailOffset : -tailOffset)
                    }
            }
        } else {
            content
                .background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.6)
                }
                .shadow(color: .black.opacity(0.12), radius: 9, y: 4)
                .overlay(alignment: placement == .abovePet ? .bottom : .top) {
                    PetBubbleTail()
                        .fill(.regularMaterial)
                        .frame(width: tailWidth, height: tailHeight)
                        .rotationEffect(.degrees(placement == .abovePet ? 0 : 180))
                        .offset(y: placement == .abovePet ? tailOffset : -tailOffset)
                }
        }
    }
}

struct PetBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.midX, y: rect.maxY)
            )
            path.closeSubpath()
        }
    }
}
