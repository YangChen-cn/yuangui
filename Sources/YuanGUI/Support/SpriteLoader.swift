import AppKit
import Foundation

enum SpriteLoader {
    private final class CacheBox {
        let cache = NSCache<NSString, NSImage>()
        private let pressureSource: DispatchSourceMemoryPressure

        init() {
            cache.countLimit = 18
            cache.totalCostLimit = 24 * 1_024 * 1_024
            pressureSource = DispatchSource.makeMemoryPressureSource(
                eventMask: [.warning, .critical],
                queue: .main
            )
            pressureSource.setEventHandler { [weak cache] in cache?.removeAllObjects() }
            pressureSource.resume()
        }
    }

    private static let box = CacheBox()

    static func image(mode: PetMode, action: PetAction) -> NSImage? {
        let key = "\(mode.resourceFolder)/\(action.file)"
        if let cached = box.cache.object(forKey: key as NSString) { return cached }
        guard let url = Bundle.module.url(
            forResource: action.file,
            withExtension: "png",
            subdirectory: "Sprites/\(mode.resourceFolder)"
        ), let image = NSImage(contentsOf: url) else { return nil }
        let cost = max(Int(image.size.width * image.size.height * 4), 1)
        box.cache.setObject(image, forKey: key as NSString, cost: cost)
        return image
    }
}
