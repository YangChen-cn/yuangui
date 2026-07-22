import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum AccessibilityTextError: LocalizedError {
    case permissionDenied
    case noFocusedElement
    case noSelection
    case targetUnavailable
    case targetChanged
    case targetReadOnly
    case replacementFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "需要开启辅助功能权限才能读取和替换其他应用中的选中文字。"
        case .noFocusedElement: "没有找到当前应用中的文字焦点。"
        case .noSelection: "请先选中一段文字。"
        case .targetUnavailable: "原应用或文字位置已经不可用。"
        case .targetChanged: "原文字或选区已经变化，为避免覆盖错误内容，本次没有替换。"
        case .targetReadOnly: "原位置不可编辑，可以复制译文后手动粘贴。"
        case let .replacementFailed(message): "替换失败：\(message)"
        }
    }
}

@MainActor
struct BrowserReplacementSnapshot: Sendable {
    let bundleIdentifier: String
}

@MainActor
struct TranslationTargetSnapshot {
    let processID: pid_t
    let applicationName: String
    let element: AXUIElement
    let originalText: String
    let fullValue: String?
    let selectedRange: CFRange?
    let role: String?
    let canReplace: Bool
    let browserReplacement: BrowserReplacementSnapshot?

    init(
        processID: pid_t,
        applicationName: String,
        element: AXUIElement,
        originalText: String,
        fullValue: String?,
        selectedRange: CFRange?,
        role: String?,
        canReplace: Bool,
        browserReplacement: BrowserReplacementSnapshot? = nil
    ) {
        self.processID = processID
        self.applicationName = applicationName
        self.element = element
        self.originalText = originalText
        self.fullValue = fullValue
        self.selectedRange = selectedRange
        self.role = role
        self.canReplace = canReplace
        self.browserReplacement = browserReplacement
    }
}

@MainActor
protocol SelectedTextProviding {
    func selectedText(promptForPermission: Bool) async throws -> TranslationTargetSnapshot
}

@MainActor
protocol AccessibilityTextReplacing {
    func replace(_ snapshot: TranslationTargetSnapshot, with text: String) async throws
}

enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func request() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
struct AccessibilitySelectedTextProvider: SelectedTextProviding {
    func selectedText(promptForPermission: Bool = true) async throws -> TranslationTargetSnapshot {
        let trusted = promptForPermission ? AccessibilityPermission.request() : AccessibilityPermission.isGranted
        guard trusted else { throw AccessibilityTextError.permissionDenied }

        let system = AXUIElementCreateSystemWide()
        let focusedApplication = copyElementAttribute(system, kAXFocusedApplicationAttribute)
        let workspaceApplication = NSWorkspace.shared.frontmostApplication
        let workspaceElement = workspaceApplication.map { AXUIElementCreateApplication($0.processIdentifier) }
        guard let focused = copyElementAttribute(system, kAXFocusedUIElementAttribute)
            ?? focusedApplication
            ?? workspaceElement else {
            throw AccessibilityTextError.noFocusedElement
        }

        // Browsers commonly expose the selection on an AXWebArea ancestor instead
        // of the nominally focused child. Check the short ancestor chain first.
        var selectionElement: AXUIElement?
        var selectedText: String?
        var browserReplacement: BrowserReplacementSnapshot?
        var candidate: AXUIElement? = focused
        for _ in 0..<10 {
            guard let current = candidate else { break }
            if let selected = copyStringAttribute(current, kAXSelectedTextAttribute),
               !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectionElement = current
                selectedText = selected
                break
            }
            candidate = copyElementAttribute(current, kAXParentAttribute)
        }

        var processID: pid_t = workspaceApplication?.processIdentifier ?? 0
        if processID == 0 { _ = AXUIElementGetPid(focused, &processID) }
        guard processID != 0 else {
            throw AccessibilityTextError.targetUnavailable
        }
        if selectedText == nil,
           let bundleIdentifier = workspaceApplication?.bundleIdentifier,
           let browserSelection = await Self.browserSelectedText(bundleIdentifier: bundleIdentifier) {
            selectedText = browserSelection.text
            selectionElement = focused
            if browserSelection.canReplace {
                browserReplacement = BrowserReplacementSnapshot(bundleIdentifier: bundleIdentifier)
            }
        }
        if selectedText == nil {
            selectedText = try await copiedSelectionFromFrontmostApplication()
            selectionElement = focused
        }
        guard let selected = selectedText,
              !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let selectionElement else { throw AccessibilityTextError.noSelection }

        let applicationName = NSRunningApplication(processIdentifier: processID)?.localizedName ?? "原应用"
        let role = copyStringAttribute(selectionElement, kAXRoleAttribute)
        let subrole = copyStringAttribute(selectionElement, kAXSubroleAttribute)
        let fullValue = copyStringAttribute(selectionElement, kAXValueAttribute)
        let range = copyRangeAttribute(selectionElement, kAXSelectedTextRangeAttribute)
        let canSetRange = isAttributeSettable(selectionElement, kAXSelectedTextRangeAttribute)
        let editableRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole]
        let rangeMatches = fullValue.flatMap { value in
            range.map { Self.substring(value, range: $0) == selected }
        } ?? false
        let isEditableRole = role.map(editableRoles.contains) == true || subrole == kAXSearchFieldSubrole
        let canReplace = browserReplacement != nil || (canSetRange && rangeMatches && isEditableRole)

        return TranslationTargetSnapshot(
            processID: processID,
            applicationName: applicationName,
            element: selectionElement,
            originalText: selected,
            fullValue: fullValue,
            selectedRange: range,
            role: role,
            canReplace: canReplace,
            browserReplacement: browserReplacement
        )
    }

    private func copiedSelectionFromFrontmostApplication() async throws -> String {
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { values, type in
                values[type] = item.data(forType: type)
            }
        } ?? []
        defer { restorePasteboard(savedItems, to: pasteboard) }

        pasteboard.clearContents()
        let menuChangeCount = pasteboard.changeCount
        if performCopyMenuAction(),
           let selected = await Self.waitForCopiedString(
            from: pasteboard,
            after: menuChangeCount,
            attempts: 25
           ) {
            return selected
        }

        let keyboardChangeCount = pasteboard.changeCount
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            throw AccessibilityTextError.noSelection
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        // Match the normal Command-C path used by the frontmost application.
        // Posting to one PID is unreliable for browsers whose web content lives
        // in a helper process, and a fixed delay is too short on slower Macs.
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        guard let selected = await Self.waitForCopiedString(
            from: pasteboard,
            after: keyboardChangeCount
        ) else {
            throw AccessibilityTextError.noSelection
        }
        return selected
    }

    private func performCopyMenuAction() -> Bool {
        guard let runningApplication = NSWorkspace.shared.frontmostApplication else { return false }
        let application = AXUIElementCreateApplication(runningApplication.processIdentifier)
        guard let menuBar = copyElementAttribute(application, kAXMenuBarAttribute) else { return false }
        return pressCopyMenuItem(in: menuBar, depth: 0)
    }

    private func pressCopyMenuItem(in element: AXUIElement, depth: Int) -> Bool {
        guard depth <= 6 else { return false }
        let role = copyStringAttribute(element, kAXRoleAttribute)
        let title = copyStringAttribute(element, kAXTitleAttribute)?.lowercased() ?? ""
        let command = copyStringAttribute(element, kAXMenuItemCmdCharAttribute)?.lowercased() ?? ""
        let enabled = copyBooleanAttribute(element, kAXEnabledAttribute) ?? true
        let copyTitles: Set<String> = ["copy", "复制", "拷贝"]
        if role == kAXMenuItemRole,
           enabled,
           (command == "c" || copyTitles.contains(title)),
           AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            return true
        }
        for child in copyElementArrayAttribute(element, kAXChildrenAttribute) {
            if pressCopyMenuItem(in: child, depth: depth + 1) { return true }
        }
        return false
    }

    nonisolated static func browserSelectionScript(for bundleIdentifier: String) -> String? {
        let javascript = """
        (()=>{const active=document.activeElement;let text='';let record=null;if(active&&/^(INPUT|TEXTAREA)$/.test(active.tagName)&&active.selectionStart!==null&&active.selectionEnd>active.selectionStart){text=active.value.slice(active.selectionStart,active.selectionEnd);record={kind:'input',element:active,start:active.selectionStart,end:active.selectionEnd,value:active.value,text:text};}else{const selection=window.getSelection();text=selection?window.getSelection().toString():'';if(text&&selection.rangeCount){const range=selection.getRangeAt(0).cloneRange();const node=range.commonAncestorContainer.nodeType===1?range.commonAncestorContainer:range.commonAncestorContainer.parentElement;const host=node&&node.closest?node.closest('[contenteditable]'):null;if(host&&host.isContentEditable){record={kind:'contenteditable',element:host,range:range,value:host.textContent,text:text};}}}window.__yuanguiTranslationSelection=record;return JSON.stringify({text:text,canReplace:!!record});})()
        """
        return browserScript(bundleIdentifier: bundleIdentifier, javascript: javascript)
    }

    nonisolated static func browserReplacementScript(
        for bundleIdentifier: String,
        originalText: String,
        replacementText: String
    ) -> String? {
        let original = javascriptStringLiteral(originalText)
        let replacement = javascriptStringLiteral(replacementText)
        let javascript = """
        (()=>{const state=window.__yuanguiTranslationSelection;const original=\(original);const replacement=\(replacement);if(!state||!state.element||!state.element.isConnected||state.text!==original)return 'changed';if(state.kind==='input'){if(state.element.value!==state.value||state.element.value.slice(state.start,state.end)!==original)return 'changed';state.element.focus();state.element.setSelectionRange(state.start,state.end);state.element.setRangeText(replacement,state.start,state.end,'end');state.element.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:replacement}));return 'ok';}if(state.kind==='contenteditable'){if(!state.range||state.range.toString()!==original||state.element.textContent!==state.value)return 'changed';state.element.focus();state.range.deleteContents();const node=document.createTextNode(replacement);state.range.insertNode(node);state.range.setStartAfter(node);state.range.collapse(true);const selection=window.getSelection();selection.removeAllRanges();selection.addRange(state.range);state.element.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:replacement}));return 'ok';}return 'readonly';})()
        """
        return browserScript(bundleIdentifier: bundleIdentifier, javascript: javascript)
    }

    nonisolated private struct BrowserSelectionResult: Decodable {
        let text: String
        let canReplace: Bool
    }

    nonisolated private static func browserSelectedText(bundleIdentifier: String) async -> BrowserSelectionResult? {
        guard let script = browserSelectionScript(for: bundleIdentifier) else { return nil }
        guard let output = await runBrowserScript(script),
              let data = output.data(using: .utf8),
              let result = try? JSONDecoder().decode(BrowserSelectionResult.self, from: data),
              !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return result
    }

    nonisolated static func runBrowserScript(_ script: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return nil
            }
            let deadline = Date().addingTimeInterval(0.7)
            while process.isRunning, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }.value
    }

    nonisolated private static func browserScript(
        bundleIdentifier: String,
        javascript: String
    ) -> String? {
        let safariIdentifiers: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
        let chromiumIdentifiers: Set<String> = [
            "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
            "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev"
        ]
        let literal = appleScriptStringLiteral(javascript)
        if safariIdentifiers.contains(bundleIdentifier) {
            return "tell application id \"\(bundleIdentifier)\"\nif (count of windows) is 0 then return \"\"\nreturn do JavaScript \(literal) in current tab of front window\nend tell"
        }
        if chromiumIdentifiers.contains(bundleIdentifier) {
            return "tell application id \"\(bundleIdentifier)\"\nif (count of windows) is 0 then return \"\"\nreturn execute active tab of front window javascript \(literal)\nend tell"
        }
        return nil
    }

    nonisolated private static func javascriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let encoded = String(data: data, encoding: .utf8) else { return "''" }
        return String(encoded.dropFirst().dropLast())
    }

    nonisolated private static func appleScriptStringLiteral(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    static func waitForCopiedString(
        from pasteboard: NSPasteboard,
        after changeCount: Int,
        attempts: Int = 70,
        pollInterval: Duration = .milliseconds(10)
    ) async -> String? {
        for _ in 0..<attempts {
            if pasteboard.changeCount != changeCount,
               let value = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
            try? await Task.sleep(for: pollInterval)
        }
        return nil
    }

    private func restorePasteboard(
        _ values: [[NSPasteboard.PasteboardType: Data]],
        to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        let items = values.map { values in
            let item = NSPasteboardItem()
            values.forEach { type, data in item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    nonisolated static func substring(_ value: String, range: CFRange) -> String? {
        guard range.location >= 0, range.length >= 0 else { return nil }
        let nsValue = value as NSString
        guard NSMaxRange(NSRange(location: range.location, length: range.length)) <= nsValue.length else { return nil }
        return nsValue.substring(with: NSRange(location: range.location, length: range.length))
    }
}

@MainActor
struct AccessibilityTextReplacementService: AccessibilityTextReplacing {
    func replace(_ snapshot: TranslationTargetSnapshot, with text: String) async throws {
        if let browserReplacement = snapshot.browserReplacement {
            try await replaceBrowserSelection(snapshot, browser: browserReplacement, with: text)
            return
        }
        guard snapshot.canReplace, let selectedRange = snapshot.selectedRange else {
            throw AccessibilityTextError.targetReadOnly
        }
        guard let runningApplication = NSRunningApplication(processIdentifier: snapshot.processID), !runningApplication.isTerminated else {
            throw AccessibilityTextError.targetUnavailable
        }
        try validate(snapshot, expectedRange: selectedRange)

        runningApplication.activate()
        try await Task.sleep(for: .milliseconds(120))

        let focusResult = AXUIElementSetAttributeValue(snapshot.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard focusResult == .success || focusResult == .attributeUnsupported else {
            throw AccessibilityTextError.replacementFailed("无法恢复原输入框焦点（\(focusResult.rawValue)）")
        }
        var restoredRange = selectedRange
        guard let rangeValue = AXValueCreate(.cfRange, &restoredRange) else {
            throw AccessibilityTextError.replacementFailed("无法恢复原选区")
        }
        let rangeResult = AXUIElementSetAttributeValue(snapshot.element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
        guard rangeResult == .success else {
            throw AccessibilityTextError.replacementFailed("无法恢复原选区（\(rangeResult.rawValue)）")
        }
        try validate(snapshot, expectedRange: selectedRange)
        try postUnicode(text, to: snapshot.processID)
    }

    private func replaceBrowserSelection(
        _ snapshot: TranslationTargetSnapshot,
        browser: BrowserReplacementSnapshot,
        with text: String
    ) async throws {
        guard let runningApplication = NSRunningApplication(processIdentifier: snapshot.processID),
              !runningApplication.isTerminated else { throw AccessibilityTextError.targetUnavailable }
        guard runningApplication.bundleIdentifier == browser.bundleIdentifier else {
            throw AccessibilityTextError.targetChanged
        }
        runningApplication.activate()
        try await Task.sleep(for: .milliseconds(80))
        guard let script = AccessibilitySelectedTextProvider.browserReplacementScript(
            for: browser.bundleIdentifier,
            originalText: snapshot.originalText,
            replacementText: text
        ), let result = await AccessibilitySelectedTextProvider.runBrowserScript(script) else {
            throw AccessibilityTextError.replacementFailed("浏览器没有返回写入结果")
        }
        switch result {
        case "ok": return
        case "changed": throw AccessibilityTextError.targetChanged
        default: throw AccessibilityTextError.targetReadOnly
        }
    }

    private func validate(_ snapshot: TranslationTargetSnapshot, expectedRange: CFRange) throws {
        guard let currentValue = copyStringAttribute(snapshot.element, kAXValueAttribute),
              let currentRange = copyRangeAttribute(snapshot.element, kAXSelectedTextRangeAttribute),
              currentRange.location == expectedRange.location,
              currentRange.length == expectedRange.length,
              AccessibilitySelectedTextProvider.substring(currentValue, range: currentRange) == snapshot.originalText else {
            throw AccessibilityTextError.targetChanged
        }
    }

    private func postUnicode(_ string: String, to processID: pid_t) throws {
        guard !string.isEmpty,
              let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            throw AccessibilityTextError.replacementFailed("无法创建文字输入事件")
        }
        let utf16 = Array(string.utf16)
        utf16.withUnsafeBufferPointer { buffer in
            guard let address = buffer.baseAddress else { return }
            keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: address)
            keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: address)
        }
        keyDown.postToPid(processID)
        keyUp.postToPid(processID)
    }
}

private func copyElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

private func copyStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? String
}

private func copyRangeAttribute(_ element: AXUIElement, _ attribute: String) -> CFRange? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cfRange else { return nil }
    var range = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
    return range
}

private func copyElementArrayAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let items = value as? [Any] else { return [] }
    return items.compactMap { item in
        let object = item as CFTypeRef
        guard CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
        return (object as! AXUIElement)
    }
}

private func copyBooleanAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? Bool
}

private func isAttributeSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
    var settable = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
