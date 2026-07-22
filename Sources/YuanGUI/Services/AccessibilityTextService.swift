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
struct TranslationTargetSnapshot {
    let processID: pid_t
    let applicationName: String
    let element: AXUIElement
    let originalText: String
    let fullValue: String?
    let selectedRange: CFRange?
    let role: String?
    let canReplace: Bool
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
        if selectedText == nil {
            selectedText = try await copiedSelectionFromFrontmostApplication(processID: processID)
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
        let canReplace = canSetRange && rangeMatches && isEditableRole

        return TranslationTargetSnapshot(
            processID: processID,
            applicationName: applicationName,
            element: selectionElement,
            originalText: selected,
            fullValue: fullValue,
            selectedRange: range,
            role: role,
            canReplace: canReplace
        )
    }

    private func copiedSelectionFromFrontmostApplication(processID: pid_t) async throws -> String {
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { values, type in
                values[type] = item.data(forType: type)
            }
        } ?? []
        defer { restorePasteboard(savedItems, to: pasteboard) }

        pasteboard.clearContents()
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            throw AccessibilityTextError.noSelection
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(processID)
        up.postToPid(processID)
        try await Task.sleep(for: .milliseconds(140))
        guard let selected = pasteboard.string(forType: .string),
              !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AccessibilityTextError.noSelection
        }
        return selected
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

private func isAttributeSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
    var settable = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
}
