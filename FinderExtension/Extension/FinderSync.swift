import AppKit
import FinderSync
import os

private let finderLog = Logger(subsystem: "com.yang.yuangui", category: "finder-extension")

final class FinderSync: FIFinderSync {
    private static let itemContextTag = 1
    private static let fileTemplateItemsOffset = 1_000
    private static let cutPasteboardType = NSPasteboard.PasteboardType(
        "com.yang.yuangui.finder-cut-payload"
    )

    private let moveQueue = DispatchQueue(label: "com.yang.yuangui.finder-extension.move")
    private var workspaceObservers: [NSObjectProtocol] = []
    private var terminalMenuSnapshot: [FinderTerminalMenuSelection] = []

    override init() {
        super.init()
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
        menu.addItem(actionItem(
            title: localized("menu.copyPath"),
            systemImage: "doc.on.doc",
            action: #selector(copyPath(_:)),
            kind: kind,
            enabled: !pathsForCopy(target: target, selected: selected, kind: kind).isEmpty
        ))
        menu.addItem(openTerminalMenuItem(directory: FinderTargetResolver.terminalDirectory(
            target: target,
            selected: selected,
            kind: kind
        )))
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
        return menu
    }

    private func openTerminalMenuItem(directory: URL?) -> NSMenuItem {
        let title = localized("menu.openTerminal")
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.image = menuImage(systemName: "terminal", accessibility: title)
        let applications = FinderTerminalApplication.installedApplications()
        parent.isEnabled = directory != nil && !applications.isEmpty
        terminalMenuSnapshot.removeAll(keepingCapacity: true)

        let submenu = NSMenu(title: title)
        if let directory {
            for application in applications {
                let item = NSMenuItem(
                    title: application.displayName,
                    action: #selector(openTerminal(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.image = application.menuImage
                item.tag = terminalMenuSnapshot.count
                terminalMenuSnapshot.append(FinderTerminalMenuSelection(
                    directoryURL: directory,
                    applicationURL: application.applicationURL
                ))
                submenu.addItem(item)
            }
        }
        parent.submenu = submenu
        return parent
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
        parent.submenu = submenu
        return parent
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

    @objc private func copyPath(_ sender: NSMenuItem) {
        let controller = FIFinderSyncController.default()
        let paths = pathsForCopy(
            target: controller.targetedURL(),
            selected: controller.selectedItemURLs() ?? [],
            kind: contextKind(from: sender)
        )
        guard !paths.isEmpty else { return }
        guard let value = FinderClipboardFormatter.pathString(
            for: paths.map { URL(fileURLWithPath: $0) }
        ) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    @objc private func openTerminal(_ sender: NSMenuItem) {
        guard terminalMenuSnapshot.indices.contains(sender.tag) else {
            presentError(localized("error.terminalUnavailable"))
            return
        }
        let selection = terminalMenuSnapshot[sender.tag]
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [selection.directoryURL],
            withApplicationAt: selection.applicationURL,
            configuration: configuration
        ) { [weak self] _, error in
            if let error {
                finderLog.error("Terminal launch failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { self?.presentError(self?.localized("error.terminalFailed") ?? "") }
            }
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
