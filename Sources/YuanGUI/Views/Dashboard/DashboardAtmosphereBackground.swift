import SwiftUI

struct DashboardAtmosphereBackground: View {
    let palette: DashboardPalette
    let mode: PetMode
    let smartState: SmartPetState

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(
        palette: DashboardPalette,
        mode: PetMode = .duo,
        smartState: SmartPetState = .normal
    ) {
        self.palette = palette
        self.mode = mode
        self.smartState = smartState
    }

    @ViewBuilder
    var body: some View {
        if palette.treatment == .liquidGlass {
            if #available(macOS 26.0, *) {
                ZStack {
                    ambientColorLayer
                    Color.clear
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            } else {
                fallbackBackground
            }
        } else {
            fallbackBackground
        }
    }

    private var fallbackBackground: some View {
        ZStack {
            ambientColorLayer
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
        }
        .clipShape(.rect(cornerRadius: 20))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var ambientColorLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    characterGlow.opacity(ambientOpacity),
                    .clear,
                    weatherGlow.opacity(ambientOpacity * 0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                Circle()
                    .fill(characterGlow.opacity(ambientOpacity * 0.82))
                .frame(width: 156, height: 156)
                .blur(radius: 32)
                .offset(x: -132, y: -208)
            Circle()
                .fill(weatherGlow.opacity(ambientOpacity * 0.68))
                .frame(width: 142, height: 142)
                .blur(radius: 36)
                .offset(x: 142, y: 218)
        }
    }

    private var ambientOpacity: Double {
        let requested = min(max(palette.ambientOpacity, 0.025), 0.12)
        let darkMultiplier = colorScheme == .dark ? 0.72 : 1
        let contrastMultiplier = colorSchemeContrast == .increased ? 0.32 : 1
        return requested * darkMultiplier * contrastMultiplier
    }

    private var characterGlow: Color {
        guard palette.treatment == .liquidGlass else {
            return palette.topGlow
        }
        return switch mode {
        case .yuanGui:
            Color(red: 0.96, green: 0.54, blue: 0.63)
        case .vcc:
            Color(red: 0.40, green: 0.66, blue: 0.98)
        case .duo:
            Color(red: 0.72, green: 0.55, blue: 0.91)
        }
    }

    private var weatherGlow: Color {
        switch smartState {
        case .normal:
            palette.bottomGlow
        case .lowBattery:
            .orange
        case .memoryPressure:
            Color(red: 0.94, green: 0.45, blue: 0.39)
        case .charging:
            .mint
        case .rainy:
            Color(red: 0.38, green: 0.62, blue: 0.94)
        case .bedtime:
            Color(red: 0.42, green: 0.40, blue: 0.78)
        }
    }
}
