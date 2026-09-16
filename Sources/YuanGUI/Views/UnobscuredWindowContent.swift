import SwiftUI

/// These split-view details already sit below the window's titlebar (and, for
/// music, a source picker). An additional scroll-edge veil obscures content.
struct UnobscuredWindowContent: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}
