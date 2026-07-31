import SwiftUI

enum YuanLiquidGlassVariant: Equatable {
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

    /// Speech bubbles default to regular glass so text remains legible over
    /// both light and dark desktops. Callers may opt into clear glass only
    /// when the underlying image has enough contrast. The tail participates
    /// in the same glass container so it visually joins the main surface.
    func yuanPetBubbleGlass(
        _ variant: YuanLiquidGlassVariant = .regular,
        cornerRadius: CGFloat,
        placement: PetAuxiliaryBubblePlacement,
        tailWidth: CGFloat,
        tailHeight: CGFloat,
        tailOffset: CGFloat,
        tailHorizontalOffset: CGFloat = 0
    ) -> some View {
        modifier(
            YuanPetBubbleGlassModifier(
                variant: variant,
                cornerRadius: cornerRadius,
                placement: placement,
                tailWidth: tailWidth,
                tailHeight: tailHeight,
                tailOffset: tailOffset,
                tailHorizontalOffset: tailHorizontalOffset
            )
        )
    }
}

struct YuanFloatingControl<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
        }
        .yuanSystemGlassButton()
        .controlSize(.small)
    }
}

struct YuanFloatingControlGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .yuanGlassEffectContainer(spacing: spacing)
    }
}

struct YuanSpeechBubbleSurface<Content: View>: View {
    let variant: YuanLiquidGlassVariant
    let cornerRadius: CGFloat
    let placement: PetAuxiliaryBubblePlacement
    let tailWidth: CGFloat
    let tailHeight: CGFloat
    let tailOffset: CGFloat
    let tailHorizontalOffset: CGFloat
    @ViewBuilder let content: Content

    init(
        variant: YuanLiquidGlassVariant,
        cornerRadius: CGFloat,
        placement: PetAuxiliaryBubblePlacement,
        tailWidth: CGFloat,
        tailHeight: CGFloat,
        tailOffset: CGFloat,
        tailHorizontalOffset: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = variant
        self.cornerRadius = cornerRadius
        self.placement = placement
        self.tailWidth = tailWidth
        self.tailHeight = tailHeight
        self.tailOffset = tailOffset
        self.tailHorizontalOffset = tailHorizontalOffset
        self.content = content()
    }

    var body: some View {
        content.yuanPetBubbleGlass(
            variant,
            cornerRadius: cornerRadius,
            placement: placement,
            tailWidth: tailWidth,
            tailHeight: tailHeight,
            tailOffset: tailOffset,
            tailHorizontalOffset: tailHorizontalOffset
        )
    }
}

struct YuanTransientPanelSurface<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content.yuanLiquidGlassSurface(.regular, cornerRadius: cornerRadius)
    }
}

struct YuanContentCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(10)
            .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 12))
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
            content.background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
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
    let variant: YuanLiquidGlassVariant
    let cornerRadius: CGFloat
    let placement: PetAuxiliaryBubblePlacement
    let tailWidth: CGFloat
    let tailHeight: CGFloat
    let tailOffset: CGFloat
    let tailHorizontalOffset: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                content
                    .glassEffect(
                        variant == .regular ? .regular : .clear,
                        in: .rect(cornerRadius: cornerRadius)
                    )
                    .overlay(alignment: placement == .abovePet ? .bottom : .top) {
                        PetBubbleTail()
                            .fill(Color.clear)
                            .frame(width: tailWidth, height: tailHeight)
                            .glassEffect(
                                variant == .regular ? .regular : .clear,
                                in: PetBubbleTail()
                            )
                            .rotationEffect(.degrees(placement == .abovePet ? 0 : 180))
                            .offset(
                                x: tailHorizontalOffset,
                                y: placement == .abovePet ? tailOffset : -tailOffset
                            )
                    }
            }
        } else {
            content
                .background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
                .overlay(alignment: placement == .abovePet ? .bottom : .top) {
                    PetBubbleTail()
                        .fill(.regularMaterial)
                        .frame(width: tailWidth, height: tailHeight)
                        .rotationEffect(.degrees(placement == .abovePet ? 0 : 180))
                        .offset(
                            x: tailHorizontalOffset,
                            y: placement == .abovePet ? tailOffset : -tailOffset
                        )
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
