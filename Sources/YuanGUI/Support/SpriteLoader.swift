import AppKit
import Foundation

enum SpriteLoader {
    enum SequenceKind {
        case idle
        case chatting
        case charging

        var frameInterval: TimeInterval {
            switch self {
            case .idle: return 0.58
            case .chatting: return 0.48
            case .charging: return 0.46
            }
        }

        var pauseAfterCycle: TimeInterval {
            switch self {
            case .idle: return 5.0
            case .chatting, .charging: return 0
            }
        }
    }

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

    static func sequenceKind(for action: PetAction) -> SequenceKind? {
        if action.file.contains("chatting") { return .chatting }
        if action.file.contains("charging") { return .charging }
        if action.file == "01-idle" || action.file == "01-loaf-idle" { return .idle }
        return nil
    }

    static func frames(mode: PetMode, action: PetAction) -> [NSImage] {
        guard let source = image(mode: mode, action: action),
              let kind = sequenceKind(for: action) else {
            return image(mode: mode, action: action).map { [$0] } ?? []
        }
        let authoredFrames = (1...6).compactMap { frame in
            loadImage(mode: mode, file: "\(action.file)-frame-\(frame)")
        }
        if authoredFrames.count == 6 { return authoredFrames }
        let transforms: [(CGFloat, CGFloat, CGFloat)]
        switch kind {
        case .idle:
            transforms = [(1, 0, 0), (1.003, 0, -0.4), (1.007, 0, -0.9), (1.003, 0, -0.4), (1, 0, 0)]
        case .chatting:
            transforms = [(1, -0.8, 0), (1.006, 0.6, -0.8), (1.002, 1.0, 0), (1.006, -0.4, -0.8), (1, -0.8, 0)]
        case .charging:
            transforms = [(1, 0, 0), (1.008, 0, -0.5), (1.014, 0, -1.0), (1.008, 0, -0.5), (1, 0, 0)]
        }
        return transforms.enumerated().compactMap { index, transform in
            let key = "frame/\(mode.resourceFolder)/\(action.file)/\(index)" as NSString
            if let cached = box.cache.object(forKey: key) { return cached }
            let frame = renderedFrame(source, scale: transform.0, x: transform.1, y: transform.2)
            let cost = max(Int(frame.size.width * frame.size.height * 4), 1)
            box.cache.setObject(frame, forKey: key, cost: cost)
            return frame
        }
    }

    static func displayFrames(mode: PetMode, action: PetAction, playsSequence: Bool) -> [NSImage] {
        if playsSequence {
            return frames(mode: mode, action: action)
        }
        return image(mode: mode, action: action).map { [$0] } ?? []
    }

    private static func renderedFrame(_ source: NSImage, scale: CGFloat, x: CGFloat, y: CGFloat) -> NSImage {
        let size = source.size
        let frame = NSImage(size: size)
        frame.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let width = size.width * scale
        let height = size.height * scale
        source.draw(
            in: NSRect(
                x: (size.width - width) / 2 + x,
                y: (size.height - height) / 2 + y,
                width: width,
                height: height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        frame.unlockFocus()
        return frame
    }

    private static func loadImage(mode: PetMode, file: String) -> NSImage? {
        let key = "\(mode.resourceFolder)/\(file)"
        if let cached = box.cache.object(forKey: key as NSString) { return cached }
        guard let url = Bundle.module.url(
            forResource: file,
            withExtension: "png",
            subdirectory: "Sprites/\(mode.resourceFolder)"
        ), let image = NSImage(contentsOf: url) else { return nil }
        let cost = max(Int(image.size.width * image.size.height * 4), 1)
        box.cache.setObject(image, forKey: key as NSString, cost: cost)
        return image
    }
}
