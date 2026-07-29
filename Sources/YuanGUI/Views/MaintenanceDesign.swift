import SwiftUI

enum MaintenanceDesign {
    static let outerPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 14
    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 11
    static let rowRadius: CGFloat = 12
    static let rowPadding: CGFloat = 12
}

struct MaintenanceHeroView: View {
    @ObservedObject var store: MaintenanceStore

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: store.isScanning ? "cat.fill" : "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.pink)
                .frame(width: 46, height: 46)
                .background(.pink.opacity(0.13), in: .circle)
                .symbolEffect(.bounce, value: store.message)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(AppLocalizer.string("清理屋"))
                    .font(.title2.bold())
                Text(AppLocalizer.string(store.message))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 10)

            if store.isScanning || store.isWorking {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(AppLocalizer.string("处理中"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .yuanLiquidGlassSurface(.clear, cornerRadius: MaintenanceDesign.cardRadius)
        .overlay(alignment: .bottom) {
            if let progress = store.scanProgress, progress.total > 0 {
                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    .tint(.pink)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 7)
            }
        }
    }
}

struct MaintenanceTabBar: View {
    @Binding var selection: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tabs: [(title: String, systemImage: String)] = [
        ("空间清理", "sparkles"),
        ("软件卸载", "shippingbox"),
        ("操作记录", "clock.arrow.circlepath")
    ]

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 6) {
                tabButtons
            }
        } else {
            tabButtons
                .background(.regularMaterial, in: .rect(cornerRadius: MaintenanceDesign.cardRadius))
        }
    }

    private var tabButtons: some View {
        HStack(spacing: 4) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                MaintenanceTabButton(
                    title: tab.title,
                    systemImage: tab.systemImage,
                    isSelected: selection == index,
                    select: {
                        withAnimation(
                            reduceMotion ? nil : .snappy(duration: 0.18)
                        ) {
                            selection = index
                        }
                    }
                )
            }
        }
        .padding(4)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }
}

private struct MaintenanceTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Label(AppLocalizer.string(title), systemImage: systemImage)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 34)
                .contentShape(.rect(cornerRadius: MaintenanceDesign.controlRadius))
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: MaintenanceDesign.controlRadius)
                    .modifier(MaintenanceTabGlassModifier())
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MaintenanceTabGlassModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(
                .regular.tint(Color.accentColor.opacity(0.08)).interactive(),
                in: .rect(cornerRadius: MaintenanceDesign.controlRadius)
            )
        } else {
            content.background(Color.accentColor.opacity(0.10))
        }
    }
}

/*
 The command surface deliberately owns one glass layer. Buttons inside it use
 the system glass button style, while macOS 15 falls back to the normal
 bordered controls through `YuanLiquidGlass`.
*/
struct MaintenanceCommandSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .yuanGlassEffectContainer(spacing: 8)
            .yuanLiquidGlassSurface(.regular, cornerRadius: MaintenanceDesign.cardRadius)
    }
}
