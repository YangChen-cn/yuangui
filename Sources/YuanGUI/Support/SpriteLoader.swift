import AppKit
import Foundation

enum SpriteLoader {
    private static var cache: [String: NSImage] = [:]

    static func image(mode: PetMode, action: PetAction) -> NSImage? {
        let key = "\(mode.resourceFolder)/\(action.file)"
        if let cached = cache[key] { return cached }
        guard let url = Bundle.module.url(
            forResource: action.file,
            withExtension: "png",
            subdirectory: "Sprites/\(mode.resourceFolder)"
        ), let image = NSImage(contentsOf: url) else { return nil }
        cache[key] = image
        return image
    }
}
