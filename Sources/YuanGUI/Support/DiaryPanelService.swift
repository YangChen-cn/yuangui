import AppKit
import UniformTypeIdentifiers

@MainActor
enum DiaryPanelService {
    static func chooseImages() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.jpeg, .png, .heic, .heif, .webP, .gif]
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseBackup() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip]
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func saveDestination(suggestedName: String, contentType: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func clipboardImage() -> DiaryImageDataSource? {
        let pasteboard = NSPasteboard.general
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return DiaryImageDataSource(data: data, originalName: "剪贴板图片.png")
    }
}
