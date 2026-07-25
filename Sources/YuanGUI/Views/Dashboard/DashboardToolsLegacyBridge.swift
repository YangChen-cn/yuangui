import SwiftUI

struct DashboardToolsLegacyBridge: View {
    @ObservedObject var store: PetStore
    @ObservedObject var quickTools: QuickToolsController
    @ObservedObject var updater: AppUpdateStore
    let openSettings: () -> Void
    let dismiss: () -> Void
    @Environment(\.appActions) private var appActions

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
                action("AI 对话", "message.fill") { appActions.open(.chat) }
                action("恋爱手账", "book.closed.fill") { appActions.open(.diary) }
                action("区域截图", "viewfinder") { quickTools.beginRegionScreenshot() }
                action("截图翻译", "text.viewfinder") { quickTools.beginScreenshotTranslation() }
                action("划词翻译", "translate") { quickTools.translateSelection() }
                action("清理屋", "sparkles") { appActions.open(.maintenance(tab: 0)) }
                action("软件卸载", "shippingbox") { appActions.open(.maintenance(tab: 1)) }
                action("设置", "gearshape", perform: openSettings)
                action("检查更新", "arrow.triangle.2.circlepath") { updater.check() }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func action(_ title: String, _ systemImage: String, perform: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage) {
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                perform()
            }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }
}
