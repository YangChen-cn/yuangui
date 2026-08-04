import AppKit
import FinderSync
import os

private let finderLog = Logger(subsystem: "com.yang.yuangui", category: "finder-extension")

final class FinderSync: FIFinderSync {
    private static let itemContextTag = 1
    private static let fileTemplateItemsOffset = 1_000
    private static let lastTerminalBundleIdentifierKey = "lastTerminalBundleIdentifier"
    private static let lastEditorBundleIdentifierKey = "lastEditorBundleIdentifier"
    private static let systemTerminalBundleIdentifier = "com.apple.Terminal"
    private static let kakuBundleIdentifier = "fun.tw93.kaku"
    private static let cutPasteboardType = NSPasteboard.PasteboardType(
        "com.yang.yuangui.finder-cut-payload"
    )

    private let moveQueue = DispatchQueue(label: "com.yang.yuangui.finder-extension.move")
    private var workspaceObservers: [NSObjectProtocol] = []
    private var terminalMenuSnapshot: [FinderApplicationMenuSelection] = []
    private var editorMenuSnapshot: [FinderApplicationMenuSelection] = []
    private var terminalApplicationsSnapshot: [FinderExternalApplication] = []
    private var editorApplicationsSnapshot: [FinderExternalApplication] = []

    override init() {
        super.init()
        if NSApp.activationPolicy() == .prohibited {
            let changed = NSApp.setActivationPolicy(.accessory)
            finderLog.info("Interactive activation policy enabled: \(changed, privacy: .public)")
        }
        refreshMonitoredVolumes()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) {
                [weak self] _ in self?.refreshMonitoredVolumes()
            },
            center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) {
                [weak self] _ in self?.refreshMonitoredVolumes()
            }
        ]
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let kind: FinderMenuContextKind
        switch menuKind {
        case .contextualMenuForContainer:
            kind = .container
        case .contextualMenuForItems:
            kind = .items
        case .contextualMenuForSidebar, .toolbarItemMenu:
            return nil
        @unknown default:
            return nil
        }

        let controller = FIFinderSyncController.default()
        let target = controller.targetedURL()
        let selected = controller.selectedItemURLs() ?? []
        let menu = NSMenu(title: "")
        menu.addItem(newFileMenuItem(kind: kind))
        if kind == .items {
            menu.addItem(actionItem(
                title: localized("menu.cut"),
                systemImage: "scissors",
                action: #selector(cutItems(_:)),
                kind: kind,
                enabled: !selected.isEmpty
            ))
        }
        let pasteDestination = FinderTargetResolver.pasteDirectory(target: target, kind: kind)
        menu.addItem(actionItem(
            title: localized("menu.paste"),
            systemImage: "doc.on.clipboard",
            action: #selector(pasteItems(_:)),
            kind: kind,
            enabled: pasteDestination != nil && readableCutPayload() != nil
        ))
        menu.addItem(copyMenuItem(kind: kind, hasPaths: !pathsForCopy(
            target: target,
            selected: selected,
            kind: kind
        ).isEmpty))
        let openTarget = FinderTargetResolver.openTarget(
            target: target,
            selected: selected,
            kind: kind
        )
        let openDirectory = FinderTargetResolver.openDirectory(
            target: target,
            selected: selected,
            kind: kind
        )
        menu.addItem(openTerminalMenuItem(directory: openDirectory))
        if openDirectory != nil && terminalApplicationsSnapshot.count > 1 {
            menu.addItem(terminalChooserMenuItem())
        }
        menu.addItem(openInEditorMenuItem(target: openTarget))
        if openTarget != nil && editorApplicationsSnapshot.count > 1 {
            menu.addItem(editorChooserMenuItem())
        }
        return menu
    }

    private func openTerminalMenuItem(directory: URL?) -> NSMenuItem {
        let title = localized("menu.openTerminal")
        let parent = NSMenuItem(title: title, action: #selector(openTerminal(_:)), keyEquivalent: "")
        parent.target = self
        parent.image = menuImage(systemName: "terminal", accessibility: title)
        let applications = FinderTerminalApplication.installedApplications()
        terminalApplicationsSnapshot = applications
        parent.isEnabled = directory != nil && !applications.isEmpty
        terminalMenuSnapshot.removeAll(keepingCapacity: true)
        parent.tag = preferredTerminalIndex(in: applications) ?? 0

        if let directory {
            for application in applications {
                terminalMenuSnapshot.append(FinderApplicationMenuSelection(
                    targetURL: directory,
                    applicationURL: application.applicationURL,
                    applicationBundleIdentifier: application.bundleIdentifier
                ))
            }
        }
        return parent
    }

    private func terminalChooserMenuItem() -> NSMenuItem {
        let title = localized("menu.chooseTerminal")
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        let preferredIndex = preferredTerminalIndex(in: terminalApplicationsSnapshot)
        for (index, application) in terminalApplicationsSnapshot.enumerated() {
            let item = NSMenuItem(
                title: application.displayName,
                action: #selector(openTerminal(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.image = application.menuImage
            item.tag = index
            item.state = index == preferredIndex ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func preferredTerminalIndex(
        in applications: [FinderExternalApplication]
    ) -> Int? {
        guard !applications.isEmpty else { return nil }
        if let savedBundleIdentifier = UserDefaults.standard.string(
            forKey: Self.lastTerminalBundleIdentifierKey
        ), let savedIndex = applications.firstIndex(where: {
            $0.bundleIdentifier == savedBundleIdentifier
        }) {
            return savedIndex
        }
        if let systemIndex = applications.firstIndex(where: {
            $0.bundleIdentifier == Self.systemTerminalBundleIdentifier
        }) {
            return systemIndex
        }
        return applications.indices.first
    }

    private func newFileMenuItem(kind: FinderMenuContextKind) -> NSMenuItem {
        let parent = NSMenuItem(title: localized("menu.newFile"), action: nil, keyEquivalent: "")
        parent.image = menuImage(systemName: "doc.badge.plus", accessibility: localized("menu.newFile"))
        let submenu = NSMenu(title: localized("menu.newFile"))
        for template in FinderFileTemplate.allCases {
            let item = actionItem(
                title: localized(template.menuTitleKey),
                systemImage: template.systemImage,
                action: #selector(createFile(_:)),
                kind: kind,
                enabled: true
            )
            let index = FinderFileTemplate.allCases.firstIndex(of: template) ?? 0
            item.tag = index + (kind == .items ? Self.fileTemplateItemsOffset : 0)
            submenu.addItem(item)
        }
        submenu.addItem(actionItem(
            title: localized("menu.blankFile"),
            systemImage: "doc.badge.plus",
            action: #selector(createBlankFile(_:)),
            kind: kind,
            enabled: true
        ))
        parent.submenu = submenu
        return parent
    }

    private func copyMenuItem(kind: FinderMenuContextKind, hasPaths: Bool) -> NSMenuItem {
        let title = localized("menu.copy")
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.image = menuImage(systemName: "doc.on.doc", accessibility: title)
        parent.isEnabled = hasPaths
        let submenu = NSMenu(title: title)
        submenu.addItem(actionItem(
            title: localized("copy.fileName"),
            systemImage: "doc.text",
            action: #selector(copyFileNames(_:)),
            kind: kind,
            enabled: true
        ))
        submenu.addItem(actionItem(
            title: localized("copy.fullPath"),
            systemImage: "doc.on.doc",
            action: #selector(copyFullPaths(_:)),
            kind: kind,
            enabled: true
        ))
        submenu.addItem(actionItem(
            title: localized("copy.terminalArgument"),
            systemImage: "terminal",
            action: #selector(copyTerminalArguments(_:)),
            kind: kind,
            enabled: true
        ))
        parent.submenu = submenu
        return parent
    }

    private func openInEditorMenuItem(target: URL?) -> NSMenuItem {
        let title = localized("menu.openEditor")
        let parent = NSMenuItem(
            title: title,
            action: #selector(openInEditor(_:)),
            keyEquivalent: ""
        )
        parent.target = self
        parent.image = menuImage(
            systemName: "chevron.left.forwardslash.chevron.right",
            accessibility: title
        )
        let applications = FinderEditorApplication.installedApplications()
        editorApplicationsSnapshot = applications
        parent.isEnabled = target != nil && !applications.isEmpty
        editorMenuSnapshot.removeAll(keepingCapacity: true)
        parent.tag = preferredEditorIndex(in: applications) ?? 0

        if let target {
            for application in applications {
                editorMenuSnapshot.append(FinderApplicationMenuSelection(
                    targetURL: target,
                    applicationURL: application.applicationURL,
                    applicationBundleIdentifier: application.bundleIdentifier
                ))
            }
        }
        return parent
    }

    private func editorChooserMenuItem() -> NSMenuItem {
        let title = localized("menu.chooseEditor")
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        let preferredIndex = preferredEditorIndex(in: editorApplicationsSnapshot)
        for (index, application) in editorApplicationsSnapshot.enumerated() {
            let item = NSMenuItem(
                title: application.displayName,
                action: #selector(openInEditor(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.image = application.menuImage
            item.tag = index
            item.state = index == preferredIndex ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func preferredEditorIndex(
        in applications: [FinderExternalApplication]
    ) -> Int? {
        guard !applications.isEmpty else { return nil }
        if let savedBundleIdentifier = UserDefaults.standard.string(
            forKey: Self.lastEditorBundleIdentifierKey
        ), let savedIndex = applications.firstIndex(where: {
            $0.bundleIdentifier == savedBundleIdentifier
        }) {
            return savedIndex
        }
        return applications.indices.first
    }

    private func actionItem(
        title: String,
        systemImage: String,
        action: Selector,
        kind: FinderMenuContextKind,
        enabled: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = kind == .container ? 0 : Self.itemContextTag
        item.image = menuImage(systemName: systemImage, accessibility: title)
        item.isEnabled = enabled
        return item
    }

    private func menuImage(systemName: String, accessibility: String) -> NSImage? {
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: accessibility)
        image?.isTemplate = true
        return image
    }

    @objc private func createFile(_ sender: NSMenuItem) {
        let templateIndex = sender.tag % Self.fileTemplateItemsOffset
        let kind: FinderMenuContextKind = sender.tag >= Self.fileTemplateItemsOffset
            ? .items
            : .container
        guard FinderFileTemplate.allCases.indices.contains(templateIndex),
              let directory = FinderTargetResolver.creationDirectory(
                target: FIFinderSyncController.default().targetedURL(),
                kind: kind
              ) else {
            presentError(localized("error.invalidDirectory"))
            return
        }
        let template = FinderFileTemplate.allCases[templateIndex]
        do {
            let url = try FinderFileCreator.create(
                template: template,
                baseName: localized(template.baseNameKey),
                in: directory
            )
            revealInFinderIfAppropriate([url])
        } catch {
            finderLog.error("File creation failed: \(error.localizedDescription, privacy: .public)")
            presentError(localized("error.createFailed"))
        }
    }

    @objc private func copyFileNames(_ sender: NSMenuItem) {
        writeCopyValue(from: sender) { FinderClipboardFormatter.fileNameString(for: $0) }
    }

    @objc private func copyFullPaths(_ sender: NSMenuItem) {
        writeCopyValue(from: sender) { FinderClipboardFormatter.pathString(for: $0) }
    }

    @objc private func copyTerminalArguments(_ sender: NSMenuItem) {
        writeCopyValue(from: sender) { FinderClipboardFormatter.terminalArgumentString(for: $0) }
    }

    private func writeCopyValue(
        from sender: NSMenuItem,
        formatter: ([URL]) -> String?
    ) {
        let controller = FIFinderSyncController.default()
        let paths = pathsForCopy(
            target: controller.targetedURL(),
            selected: controller.selectedItemURLs() ?? [],
            kind: contextKind(from: sender)
        )
        guard !paths.isEmpty else { return }
        guard let value = formatter(paths.map { URL(fileURLWithPath: $0) }) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    @objc private func createBlankFile(_ sender: NSMenuItem) {
        guard let directory = FinderTargetResolver.creationDirectory(
            target: FIFinderSyncController.default().targetedURL(),
            kind: contextKind(from: sender)
        ) else {
            presentError(localized("error.invalidDirectory"))
            return
        }
        // Finder is still tracking its context menu while the action is
        // delivered. Defer the alert until that menu has closed, otherwise
        // AppKit can order the dialog behind Finder and the action appears to
        // do nothing.
        promptForBlankFileName { [weak self] name in
            guard let self, let name else { return }
            do {
                let url = try FinderFileCreator.create(named: name, in: directory)
                self.revealInFinderIfAppropriate([url])
            } catch FinderFileCreationError.emptyName {
                self.presentError(self.localized("blankFile.error.nameRequired"))
            } catch FinderFileCreationError.invalidName {
                self.presentError(self.localized("blankFile.error.invalidName"))
            } catch {
                finderLog.error("Blank file creation failed: \(error.localizedDescription, privacy: .public)")
                self.presentError(self.localized("blankFile.error.failed"))
            }
        }
    }

    private func promptForBlankFileName(completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            BlankFilePromptController(
                title: self.localized("blankFile.prompt.title"),
                fieldAccessibilityLabel: self.localized("blankFile.prompt.fieldLabel"),
                placeholder: self.localized("blankFile.prompt.placeholder"),
                confirmTitle: self.localized("blankFile.prompt.create"),
                cancelTitle: self.localized("action.cancel"),
                completion: completion
            ).present()
        }
    }

    @objc private func openInEditor(_ sender: NSMenuItem) {
        guard editorMenuSnapshot.indices.contains(sender.tag) else {
            presentError(localized("error.editorUnavailable"))
            return
        }
        let selection = editorMenuSnapshot[sender.tag]
        UserDefaults.standard.set(
            selection.applicationBundleIdentifier,
            forKey: Self.lastEditorBundleIdentifierKey
        )
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [selection.targetURL],
            withApplicationAt: selection.applicationURL,
            configuration: configuration
        ) { [weak self] _, error in
            if let error {
                finderLog.error("Editor launch failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { self?.presentError(self?.localized("error.editorFailed") ?? "") }
            }
        }
    }

    @objc private func openTerminal(_ sender: NSMenuItem) {
        guard terminalMenuSnapshot.indices.contains(sender.tag) else {
            presentError(localized("error.terminalUnavailable"))
            return
        }
        let selection = terminalMenuSnapshot[sender.tag]
        UserDefaults.standard.set(
            selection.applicationBundleIdentifier,
            forKey: Self.lastTerminalBundleIdentifierKey
        )
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if selection.applicationBundleIdentifier == Self.kakuBundleIdentifier {
            // Kaku treats a Finder document-open event as a file import. Its
            // current macOS build can crash when that event contains a folder;
            // use Kaku's native CLI arguments through LaunchServices instead.
            configuration.arguments = ["start", "--cwd", selection.targetURL.path]
            NSWorkspace.shared.openApplication(
                at: selection.applicationURL,
                configuration: configuration
            ) { [weak self] _, error in
                self?.handleTerminalLaunchResult(error)
            }
        } else {
            NSWorkspace.shared.open(
                [selection.targetURL],
                withApplicationAt: selection.applicationURL,
                configuration: configuration
            ) { [weak self] _, error in
                self?.handleTerminalLaunchResult(error)
            }
        }
    }

    private func handleTerminalLaunchResult(_ error: Error?) {
        guard let error else { return }
        finderLog.error("Terminal launch failed: \(error.localizedDescription, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            self?.presentError(self?.localized("error.terminalFailed") ?? "")
        }
    }

    @objc private func cutItems(_ sender: NSMenuItem) {
        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        let items = selected.compactMap { try? FinderCutItem.capture($0) }
        guard !items.isEmpty else {
            presentError(localized("error.cutFailed"))
            return
        }
        writeCutPayload(FinderCutPayload(items: items))
    }

    @objc private func pasteItems(_ sender: NSMenuItem) {
        guard let payload = readableCutPayload(),
              let destination = FinderTargetResolver.pasteDirectory(
                target: FIFinderSyncController.default().targetedURL(),
                kind: contextKind(from: sender)
              ) else { return }

        moveQueue.async { [weak self] in
            let result = FinderMoveService.move(payload, to: destination)
            DispatchQueue.main.async {
                self?.finishPaste(payload: payload, result: result)
            }
        }
    }

    private func finishPaste(payload: FinderCutPayload, result: FinderMoveResult) {
        if readableCutPayload()?.token == payload.token {
            if result.remainingItems.isEmpty {
                NSPasteboard.general.clearContents()
            } else {
                writeCutPayload(FinderCutPayload(token: payload.token, items: result.remainingItems))
            }
        }
        if !result.movedURLs.isEmpty {
            revealInFinderIfAppropriate(result.movedURLs)
        }
        if !result.failures.isEmpty {
            presentError(String(
                format: localized("error.pastePartial"),
                result.movedURLs.count,
                result.failures.count
            ))
        }
    }

    private func writeCutPayload(_ payload: FinderCutPayload) {
        guard let data = try? FinderCutPayloadCodec.encode(payload) else { return }
        let metadata = NSPasteboardItem()
        metadata.setData(data, forType: Self.cutPasteboardType)
        var objects: [NSPasteboardWriting] = [metadata]
        objects.append(contentsOf: payload.items.map { $0.url as NSURL })
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(objects)
    }

    private func readableCutPayload() -> FinderCutPayload? {
        guard let data = NSPasteboard.general.pasteboardItems?
            .compactMap({ $0.data(forType: Self.cutPasteboardType) })
            .first,
            let payload = FinderCutPayloadCodec.decode(data) else { return nil }
        return payload
    }

    private func pathsForCopy(
        target: URL?,
        selected: [URL],
        kind: FinderMenuContextKind
    ) -> [String] {
        let urls = kind == .items && !selected.isEmpty ? selected : target.map { [$0] } ?? []
        return urls.compactMap(FinderTargetResolver.normalizedFileURL).map(\.path)
    }

    private func contextKind(from item: NSMenuItem) -> FinderMenuContextKind {
        item.tag == Self.itemContextTag ? .items : .container
    }

    private func revealInFinderIfAppropriate(_ urls: [URL]) {
        guard let first = urls.first,
              !FinderTargetResolver.isDesktopDirectory(first.deletingLastPathComponent()) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func refreshMonitoredVolumes() {
        let keys: [URLResourceKey] = [
            .volumeIsLocalKey,
            .volumeIsBrowsableKey,
            .volumeIsInternalKey
        ]
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []
        let externalLocalVolumes = mounted.filter { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            return values.volumeIsLocal == true
                && values.volumeIsBrowsable != false
                && values.volumeIsInternal == false
        }
        FIFinderSyncController.default().directoryURLs = Set(
            [URL(fileURLWithPath: "/", isDirectory: true)] + externalLocalVolumes
        )
    }

    private func presentError(_ message: String) {
        guard !message.isEmpty else { return }
        NSSound.beep()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localized("error.title")
        alert.informativeText = message
        alert.addButton(withTitle: localized("action.ok"))
        alert.runModal()
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, bundle: Bundle(for: FinderSync.self), comment: "")
    }
}

private final class BlankFilePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class BlankFilePromptController: NSObject {
    private let panel: BlankFilePanel
    private let field: NSTextField
    private let completion: (String?) -> Void

    init(
        title: String,
        fieldAccessibilityLabel: String,
        placeholder: String,
        confirmTitle: String,
        cancelTitle: String,
        completion: @escaping (String?) -> Void
    ) {
        self.completion = completion
        panel = BlankFilePanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 132),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        field = NSTextField(frame: .zero)
        super.init()

        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .utilityWindow
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let content = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 360, height: 132))
        content.material = .popover
        content.blendingMode = .behindWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 12
        content.layer?.masksToBounds = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        field.placeholderString = placeholder
        field.setAccessibilityLabel(fieldAccessibilityLabel)
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.controlSize = .regular
        field.target = self
        field.action = #selector(accept)
        field.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(
            title: cancelTitle,
            target: self,
            action: #selector(cancel)
        )
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .regular
        cancelButton.keyEquivalent = "\u{1b}"

        let confirmButton = NSButton(
            title: confirmTitle,
            target: self,
            action: #selector(accept)
        )
        confirmButton.bezelStyle = .rounded
        confirmButton.controlSize = .regular
        confirmButton.keyEquivalent = "\r"

        let buttonStack = NSStackView(views: [cancelButton, confirmButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(titleLabel)
        content.addSubview(field)
        content.addSubview(buttonStack)
        panel.contentView = content
        panel.initialFirstResponder = field

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            field.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            field.heightAnchor.constraint(equalToConstant: 26),
            buttonStack.topAnchor.constraint(greaterThanOrEqualTo: field.bottomAnchor, constant: 12),
            buttonStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            buttonStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
            confirmButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 76)
        ])
    }

    func present() {
        let wasActive = NSApp.isActive
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        field.selectText(nil)
        DispatchQueue.main.async { [self] in
            self.panel.makeKey()
            self.panel.makeFirstResponder(self.field)
        }
        let response = NSApp.runModal(for: panel)
        panel.orderOut(nil)
        if !wasActive {
            NSApp.deactivate()
        }
        completion(response == .OK ? field.stringValue : nil)
    }

    @objc private func accept() {
        NSApp.stopModal(withCode: .OK)
    }

    @objc private func cancel() {
        NSApp.stopModal(withCode: .cancel)
    }
}

private extension FinderFileTemplate {
    var menuTitleKey: String {
        switch self {
        case .text: "file.text.title"
        case .markdown: "file.markdown.title"
        case .word: "file.word.title"
        case .excel: "file.excel.title"
        case .powerpoint: "file.powerpoint.title"
        }
    }

    var baseNameKey: String {
        switch self {
        case .text: "file.text.baseName"
        case .markdown: "file.markdown.baseName"
        case .word: "file.word.baseName"
        case .excel: "file.excel.baseName"
        case .powerpoint: "file.powerpoint.baseName"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "doc.plaintext"
        case .markdown: "text.document"
        case .word: "doc.richtext"
        case .excel: "tablecells"
        case .powerpoint: "rectangle.on.rectangle"
        }
    }
}
