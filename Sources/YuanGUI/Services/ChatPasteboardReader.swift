import AppKit
import Foundation
import UniformTypeIdentifiers

struct PastedChatImage {
    enum Source {
        case data(Data)
        case fileURL(URL)
    }

    let source: Source
    let suggestedName: String
}

enum ChatPasteboardReader {
    static func images(from pasteboard: NSPasteboard = .general) -> [PastedChatImage] {
        let fileImages = fileImageURLs(from: pasteboard).map {
            PastedChatImage(source: .fileURL($0), suggestedName: $0.lastPathComponent)
        }
        if !fileImages.isEmpty { return fileImages }

        let itemImages: [PastedChatImage] = (pasteboard.pasteboardItems ?? []).enumerated().compactMap { index, item -> PastedChatImage? in
            guard let type = item.types.first(where: { type in
                UTType(type.rawValue)?.conforms(to: .image) == true
            }), let data = item.data(forType: type), !data.isEmpty else {
                return nil
            }
            let fileExtension = UTType(type.rawValue)?.preferredFilenameExtension ?? "png"
            return PastedChatImage(
                source: .data(data),
                suggestedName: "粘贴图片-\(index + 1).\(fileExtension)"
            )
        }
        if !itemImages.isEmpty { return itemImages }

        // Some apps expose only an NSImage-compatible pasteboard object rather
        // than a public image data type. Convert that last-resort representation
        // at the AppKit boundary before it reaches the chat attachment pipeline.
        guard let image = NSImage(pasteboard: pasteboard),
              let data = image.tiffRepresentation else {
            return []
        }
        return [PastedChatImage(source: .data(data), suggestedName: "粘贴图片-1.tiff")]
    }

    private static func fileImageURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        return objects.compactMap { object in
            let url: URL?
            if let value = object as? URL {
                url = value
            } else if let value = object as? NSURL {
                url = value as URL
            } else {
                url = nil
            }
            guard let url,
                  let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
                  values.contentType?.conforms(to: .image) == true else {
                return nil
            }
            return url
        }
    }
}
