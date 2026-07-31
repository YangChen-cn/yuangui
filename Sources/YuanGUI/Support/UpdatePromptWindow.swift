import AppKit
import SwiftUI

@MainActor
final class UpdatePromptModel: ObservableObject {
    @Published private(set) var currentVersion = ""
    @Published private(set) var releaseVersion = ""
    @Published private(set) var highlights: [String] = []

    var onInstall: (() -> Void)?
    var onLater: (() -> Void)?
    var onShowDetails: (() -> Void)?

    func configure(
        currentVersion: String,
        releaseVersion: String,
        highlights: [String],
        onInstall: @escaping () -> Void,
        onLater: @escaping () -> Void,
        onShowDetails: @escaping () -> Void
    ) {
        self.currentVersion = currentVersion
        self.releaseVersion = releaseVersion
        self.highlights = highlights
        self.onInstall = onInstall
        self.onLater = onLater
        self.onShowDetails = onShowDetails
    }

    func clearActions() {
        onInstall = nil
        onLater = nil
        onShowDetails = nil
    }
}

struct UpdateAvailablePromptView: View {
    @ObservedObject var model: UpdatePromptModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalizer.string("update.auto.prompt.title"))
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(AppLocalizer.format(
                        "update.auto.prompt.versionTransition",
                        model.currentVersion,
                        model.releaseVersion
                    ))
                    .font(.subheadline.monospaced().weight(.medium))
                    .foregroundStyle(.secondary)
                }
            }

            if !model.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalizer.string("update.auto.prompt.highlights"))
                        .font(.headline)
                    ForEach(model.highlights.prefix(2), id: \.self) { highlight in
                        Label {
                            Text(highlight)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .accessibilityHidden(true)
                        }
                    }
                }
            }

            Text(AppLocalizer.string("update.auto.prompt.safeInstall"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(AppLocalizer.string("update.auto.prompt.later")) {
                    model.onLater?()
                }
                .keyboardShortcut(.escape)

                Button(AppLocalizer.string("update.auto.prompt.details")) {
                    model.onShowDetails?()
                }

                Button(AppLocalizer.string("update.auto.prompt.install")) {
                    model.onInstall?()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 460, maxWidth: 500)
        .containerBackground(.regularMaterial, for: .window)
    }
}

/// Pure geometry and screen-selection helpers for the update prompt. Keeping
/// these separate from NSPanel setup makes multiple-monitor behavior unit
/// testable without displaying a real window.
enum UpdatePromptWindowPlacement {
    static func constrainedWindowSize(windowSize: CGSize, visibleFrame: CGRect) -> CGSize {
        let preferredWidth = min(max(windowSize.width, 440), 500)
        let preferredHeight = min(max(windowSize.height, 250), 360)
        return CGSize(
            width: min(preferredWidth, visibleFrame.width),
            height: min(preferredHeight, visibleFrame.height)
        )
    }

    static func centeredOrigin(windowSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        let x = windowSize.width > visibleFrame.width
            ? visibleFrame.minX
            : visibleFrame.midX - windowSize.width / 2
        let y = windowSize.height > visibleFrame.height
            ? visibleFrame.minY
            : visibleFrame.midY - windowSize.height / 2
        return CGPoint(x: x, y: y)
    }

    static func centeredFrame(windowSize: CGSize, visibleFrame: CGRect) -> CGRect {
        let size = constrainedWindowSize(windowSize: windowSize, visibleFrame: visibleFrame)
        return CGRect(origin: centeredOrigin(windowSize: size, visibleFrame: visibleFrame), size: size)
    }

    static func targetScreen(
        keyWindow: NSWindow?,
        mainWindow: NSWindow?,
        mouseLocation: NSPoint,
        screens: [NSScreen],
        excluding excludedWindow: NSWindow? = nil
    ) -> NSScreen? {
        let isCandidate: (NSWindow) -> Bool = { window in
            guard window !== excludedWindow,
                  window.isVisible,
                  !window.isMiniaturized,
                  !window.styleMask.contains(.nonactivatingPanel),
                  window.styleMask.contains(.titled)
            else { return false }
            return true
        }

        for window in [keyWindow, mainWindow].compactMap({ $0 }) where isCandidate(window) {
            if let screen = window.screen, screens.contains(where: { $0 === screen }) {
                return screen
            }
        }

        if let mouseScreen = screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return mouseScreen
        }
        return NSScreen.main.flatMap { main in
            screens.first(where: { $0 === main })
        } ?? screens.first
    }
}

private final class UpdatePromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class UpdateAvailableWindowController: NSWindowController, NSWindowDelegate, UpdatePromptPresenting {
    private let model = UpdatePromptModel()
    private lazy var hostingView = NSHostingView(rootView: UpdateAvailablePromptView(model: model))
    private var hasFinishedCurrentPresentation = true

    private var promptPanel: UpdatePromptPanel { window as! UpdatePromptPanel }

    convenience init() {
        self.init(window: nil)
    }

    override init(window: NSWindow?) {
        let panel = UpdatePromptPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        panel.title = AppLocalizer.string("update.auto.window.title")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.delegate = self
        panel.contentView = hostingView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isPresenting: Bool { !hasFinishedCurrentPresentation }

    func presentUpdate(
        currentVersion: String,
        release: GitHubRelease,
        highlights: [String],
        onInstall: @escaping () -> Void,
        onLater: @escaping () -> Void,
        onShowDetails: @escaping () -> Void
    ) {
        guard !isPresenting else { return }
        hasFinishedCurrentPresentation = false

        model.configure(
            currentVersion: currentVersion,
            releaseVersion: release.version,
            highlights: highlights,
            onInstall: { [weak self] in
                self?.finish { onInstall() }
            },
            onLater: { [weak self] in
                self?.finish { onLater() }
            },
            onShowDetails: { [weak self] in
                self?.finish { onShowDetails() }
            }
        )

        let screens = NSScreen.screens
        let target = UpdatePromptWindowPlacement.targetScreen(
            keyWindow: NSApp.keyWindow,
            mainWindow: NSApp.mainWindow,
            mouseLocation: NSEvent.mouseLocation,
            screens: screens,
            excluding: promptPanel
        ) ?? NSScreen.main

        if let target {
            let contentSize = UpdatePromptWindowPlacement.constrainedWindowSize(
                windowSize: hostingView.fittingSize,
                visibleFrame: target.visibleFrame
            )
            promptPanel.setContentSize(contentSize)
            let frame = UpdatePromptWindowPlacement.centeredFrame(
                windowSize: promptPanel.frame.size,
                visibleFrame: target.visibleFrame
            )
            promptPanel.setFrame(frame, display: false)
        }

        if NSApp.isActive {
            promptPanel.makeKeyAndOrderFront(nil)
        } else {
            // The coordinator normally prevents this path. Keeping it
            // non-activating is an additional guard against focus stealing.
            promptPanel.orderFront(nil)
        }
    }

    func dismiss() {
        finish()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish()
        return false
    }

    private func finish(_ action: (() -> Void)? = nil) {
        guard !hasFinishedCurrentPresentation else { return }
        hasFinishedCurrentPresentation = true
        model.clearActions()
        promptPanel.orderOut(nil)
        action?()
    }
}
