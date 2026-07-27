import AppKit
import Carbon.HIToolbox
import Foundation

enum QuickToolAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case regionScreenshot
    case screenshotTranslation
    case translateSelection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regionScreenshot: AppLocalizer.string("区域截图")
        case .screenshotTranslation: AppLocalizer.string("截图翻译")
        case .translateSelection: AppLocalizer.string("翻译所选文字")
        }
    }
}

struct HotKeyModifiers: OptionSet, Codable, Equatable, Sendable {
    let rawValue: UInt8

    static let command = HotKeyModifiers(rawValue: 1 << 0)
    static let option = HotKeyModifiers(rawValue: 1 << 1)
    static let control = HotKeyModifiers(rawValue: 1 << 2)
    static let shift = HotKeyModifiers(rawValue: 1 << 3)

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        var value: HotKeyModifiers = []
        let flags = eventFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.shift) { value.insert(.shift) }
        self = value
    }

    var carbonValue: UInt32 {
        var value: UInt32 = 0
        if contains(.command) { value |= UInt32(cmdKey) }
        if contains(.option) { value |= UInt32(optionKey) }
        if contains(.control) { value |= UInt32(controlKey) }
        if contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    var symbols: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

struct HotKeyBinding: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: HotKeyModifiers
    let keyLabel: String

    static let screenshotDefault = HotKeyBinding(
        keyCode: UInt32(kVK_ANSI_A),
        modifiers: [.control],
        keyLabel: "A"
    )

    static let screenshotTranslationDefault = HotKeyBinding(
        keyCode: UInt32(kVK_ANSI_A),
        modifiers: [.control, .shift],
        keyLabel: "A"
    )

    static let translationDefault = HotKeyBinding(
        keyCode: UInt32(kVK_ANSI_Z),
        modifiers: [.control],
        keyLabel: "Z"
    )

    var displayText: String { modifiers.symbols + keyLabel }

    var validationMessage: String? {
        guard !keyLabel.isEmpty else { return "请选择一个按键。" }
        guard modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control) else {
            return "快捷键至少需要包含 Control、Option 或 Command。"
        }
        if modifiers == [.command, .shift], [UInt32(kVK_ANSI_3), UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5)].contains(keyCode) {
            return "该组合是 macOS 系统截图快捷键。"
        }
        return nil
    }
}

enum QuickToolLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simplifiedChinese: AppLocalizer.string("简体中文")
        case .english: AppLocalizer.string("英语")
        case .japanese: AppLocalizer.string("日语")
        case .korean: AppLocalizer.string("韩语")
        case .french: AppLocalizer.string("法语")
        case .german: AppLocalizer.string("德语")
        case .spanish: AppLocalizer.string("西班牙语")
        }
    }
}

enum TranslationEngine: String, CaseIterable, Codable, Identifiable, Sendable {
    case systemShortcut
    case system
    case onlineAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemShortcut: AppLocalizer.string("系统快捷指令")
        case .system: AppLocalizer.string("系统离线")
        case .onlineAI: AppLocalizer.string("在线 AI")
        }
    }
}

enum ScreenshotTool: String, CaseIterable, Identifiable, Sendable {
    case pen
    case highlighter
    case line
    case arrow
    case rectangle
    case ellipse
    case text
    case mosaic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: AppLocalizer.string("画笔")
        case .highlighter: AppLocalizer.string("高亮")
        case .line: AppLocalizer.string("直线")
        case .arrow: AppLocalizer.string("箭头")
        case .rectangle: AppLocalizer.string("矩形")
        case .ellipse: AppLocalizer.string("椭圆")
        case .text: AppLocalizer.string("文字")
        case .mosaic: AppLocalizer.string("马赛克")
        }
    }

    var systemImage: String {
        switch self {
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .text: "textformat"
        case .mosaic: "square.grid.3x3.fill"
        }
    }
}

struct AnnotationStyle: Equatable {
    var color: NSColor
    var lineWidth: CGFloat
    var fontSize: CGFloat
}

enum ScreenshotAnnotation: Identifiable, Equatable {
    case stroke(id: UUID, points: [CGPoint], style: AnnotationStyle, highlighter: Bool)
    case line(id: UUID, start: CGPoint, end: CGPoint, style: AnnotationStyle, arrow: Bool)
    case rectangle(id: UUID, rect: CGRect, style: AnnotationStyle, ellipse: Bool)
    case text(id: UUID, origin: CGPoint, text: String, style: AnnotationStyle)
    case mosaic(id: UUID, points: [CGPoint], width: CGFloat)

    var id: UUID {
        switch self {
        case let .stroke(id, _, _, _), let .line(id, _, _, _, _), let .rectangle(id, _, _, _),
             let .text(id, _, _, _), let .mosaic(id, _, _): id
        }
    }
}
