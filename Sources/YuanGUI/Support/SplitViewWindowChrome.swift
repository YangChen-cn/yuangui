import AppKit

/// Titlebar configuration for windows whose content is a `NavigationSplitView`.
///
/// On macOS 26/27 `NavigationSplitView` installs an `NSTitlebarBackgroundView`
/// at the top of its own content, assuming the hosting window extends content
/// under the titlebar. Every YuanGUI window keeps the standard `.titled`
/// layout instead, so that view lands *below* the real titlebar — over the
/// first lines of the detail column — and paints an opaque strip there. That
/// is the white bar across the top of the settings, diary, chat history and
/// music windows.
///
/// A transparent titlebar makes AppKit paint nothing in that view. Nothing
/// else changes: the window keeps its size, title, toolbar and the system
/// sidebar toggle, and no content is inset or padded.
enum SplitViewWindowChrome {
    static func apply(to window: NSWindow) {
        window.titlebarAppearsTransparent = true
    }
}
