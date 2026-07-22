import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ScreenshotOutputError: LocalizedError {
    case contextCreationFailed
    case imageCreationFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .contextCreationFailed: "无法创建图片编辑画布。"
        case .imageCreationFailed: "无法生成编辑后的图片。"
        case .encodingFailed: "无法编码 PNG 图片。"
        }
    }
}

struct ScreenshotOutputService {
    func pngData(image: CGImage, annotations: [ScreenshotAnnotation]) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try ScreenshotRenderer.pngData(image: image, annotations: annotations)
        }.value
    }

    @MainActor
    func copyPNG(_ data: Data) throws {
        guard let image = NSImage(data: data) else { throw ScreenshotOutputError.imageCreationFailed }
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        if let tiff = image.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw ScreenshotOutputError.encodingFailed }
    }

    func savePNG(_ data: Data, directoryPath: String, now: Date = Date()) throws -> URL {
        let directory = URL(fileURLWithPath: directoryPath, isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let baseName = "YuanGUI \(formatter.string(from: now))"
        var destination = directory.appendingPathComponent(baseName).appendingPathExtension("png")
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(baseName) \(suffix)").appendingPathExtension("png")
            suffix += 1
        }
        try data.write(to: destination, options: .atomic)
        return destination
    }
}

enum ScreenshotRenderer {
    static func pngData(image: CGImage, annotations: [ScreenshotAnnotation]) throws -> Data {
        guard let rendered = render(image: image, annotations: annotations) else {
            throw ScreenshotOutputError.imageCreationFailed
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ScreenshotOutputError.encodingFailed
        }
        CGImageDestinationAddImage(destination, rendered, nil)
        guard CGImageDestinationFinalize(destination) else { throw ScreenshotOutputError.encodingFailed }
        return data as Data
    }

    static func render(image: CGImage, annotations: [ScreenshotAnnotation]) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        drawAnnotations(annotations, image: image, in: context)
        return context.makeImage()
    }

    static func drawAnnotations(_ annotations: [ScreenshotAnnotation], image: CGImage, in context: CGContext) {
        let pixelated = annotations.contains(where: {
            if case .mosaic = $0 { return true }
            return false
        }) ? pixelatedImage(image) : nil

        for annotation in annotations {
            switch annotation {
            case let .stroke(_, points, style, _):
                guard points.count > 1 else { continue }
                context.saveGState()
                context.setStrokeColor(style.color.cgColor)
                context.setLineWidth(style.lineWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                let path = CGMutablePath()
                path.move(to: points[0])
                points.dropFirst().forEach { path.addLine(to: $0) }
                context.addPath(path)
                context.strokePath()
                context.restoreGState()

            case let .line(_, start, end, style, arrow):
                context.saveGState()
                context.setStrokeColor(style.color.cgColor)
                context.setFillColor(style.color.cgColor)
                context.setLineWidth(style.lineWidth)
                context.setLineCap(.round)
                context.move(to: start)
                context.addLine(to: end)
                context.strokePath()
                if arrow { drawArrowHead(from: start, to: end, style: style, in: context) }
                context.restoreGState()

            case let .rectangle(_, rect, style, ellipse):
                context.saveGState()
                context.setStrokeColor(style.color.cgColor)
                context.setLineWidth(style.lineWidth)
                if ellipse { context.strokeEllipse(in: rect) } else { context.stroke(rect) }
                context.restoreGState()

            case let .text(_, origin, text, style):
                context.saveGState()
                let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = graphicsContext
                text.draw(at: origin, withAttributes: [
                    .font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold),
                    .foregroundColor: style.color
                ])
                NSGraphicsContext.restoreGraphicsState()
                context.restoreGState()

            case let .mosaic(_, points, width):
                guard points.count > 1, let pixelated else { continue }
                context.saveGState()
                let path = CGMutablePath()
                path.move(to: points[0])
                points.dropFirst().forEach { path.addLine(to: $0) }
                let stroked = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 2)
                context.addPath(stroked)
                context.clip()
                context.interpolationQuality = .none
                context.draw(pixelated, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                context.restoreGState()
            }
        }
    }

    private static func drawArrowHead(from start: CGPoint, to end: CGPoint, style: AnnotationStyle, in context: CGContext) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(12, style.lineWidth * 3.2)
        let spread = CGFloat.pi / 7
        let p1 = CGPoint(x: end.x - cos(angle - spread) * length, y: end.y - sin(angle - spread) * length)
        let p2 = CGPoint(x: end.x - cos(angle + spread) * length, y: end.y - sin(angle + spread) * length)
        let path = CGMutablePath()
        path.move(to: end)
        path.addLine(to: p1)
        path.move(to: end)
        path.addLine(to: p2)
        context.addPath(path)
        context.strokePath()
    }

    private static func pixelatedImage(_ image: CGImage) -> CGImage? {
        let block = 12
        let smallWidth = max(1, image.width / block)
        let smallHeight = max(1, image.height / block)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let smallContext = CGContext(
                data: nil,
                width: smallWidth,
                height: smallHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        smallContext.interpolationQuality = .low
        smallContext.draw(image, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        return smallContext.makeImage()
    }
}
