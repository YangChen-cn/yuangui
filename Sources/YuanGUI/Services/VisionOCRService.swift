import CoreGraphics
import Foundation
import Vision

struct OCRBackgroundColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let white = OCRBackgroundColor(red: 1, green: 1, blue: 1)

    var isDark: Bool {
        red * 0.2126 + green * 0.7152 + blue * 0.0722 < 0.48
    }
}

struct OCRTextRegion: Equatable, Sendable {
    let text: String
    /// Vision coordinates: normalized to 0...1 with the origin at bottom-left.
    let normalizedRect: CGRect
    let backgroundColor: OCRBackgroundColor

    init(
        text: String,
        normalizedRect: CGRect,
        backgroundColor: OCRBackgroundColor = .white
    ) {
        self.text = text
        self.normalizedRect = normalizedRect
        self.backgroundColor = backgroundColor
    }
}

struct OCRRecognition: Equatable, Sendable {
    let regions: [OCRTextRegion]

    var text: String {
        regions.map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

protocol OCRTextRecognizing: Sendable {
    func recognizeText(in image: CGImage) async throws -> String
    func recognizeLayout(in image: CGImage) async throws -> OCRRecognition
}

extension OCRTextRecognizing {
    func recognizeLayout(in image: CGImage) async throws -> OCRRecognition {
        let text = try await recognizeText(in: image)
        guard !text.isEmpty else { return OCRRecognition(regions: []) }
        return OCRRecognition(regions: [OCRTextRegion(
            text: text,
            normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1)
        )])
    }
}

enum VisionOCRError: LocalizedError {
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .recognitionFailed(message): "截图文字识别失败：\(message)"
        }
    }
}

struct VisionOCRService: OCRTextRecognizing {
    func recognizeText(in image: CGImage) async throws -> String {
        try await recognizeLayout(in: image).text
    }

    func recognizeLayout(in image: CGImage) async throws -> OCRRecognition {
        try await Task.detached(priority: .userInitiated) {
            let backgroundSampler = ImageBackgroundSampler(image: image)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let preferredLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
            if let supported = try? request.supportedRecognitionLanguages() {
                request.recognitionLanguages = preferredLanguages.filter(supported.contains)
            }

            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch {
                throw VisionOCRError.recognitionFailed(error.localizedDescription)
            }

            let regions = (request.results ?? [])
                .sorted(by: Self.isBeforeInReadingOrder)
                .compactMap { observation -> OCRTextRegion? in
                    guard let text = observation.topCandidates(1).first?.string
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                          !text.isEmpty else { return nil }
                    return OCRTextRegion(
                        text: text,
                        normalizedRect: observation.boundingBox,
                        backgroundColor: backgroundSampler?.color(around: observation.boundingBox) ?? .white
                    )
                }
            return OCRRecognition(regions: regions)
        }.value
    }

    private static func isBeforeInReadingOrder(
        _ lhs: VNRecognizedTextObservation,
        _ rhs: VNRecognizedTextObservation
    ) -> Bool {
        let lineTolerance = max(lhs.boundingBox.height, rhs.boundingBox.height) * 0.5
        if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > lineTolerance {
            return lhs.boundingBox.midY > rhs.boundingBox.midY
        }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }
}

private struct ImageBackgroundSampler {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(image: CGImage) {
        let pixelWidth = image.width
        let pixelHeight = image.height
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        var storage = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        let created = storage.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.translateBy(x: 0, y: CGFloat(pixelHeight))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            return true
        }
        guard created else { return nil }
        width = pixelWidth
        height = pixelHeight
        pixels = storage
    }

    func color(around rect: CGRect) -> OCRBackgroundColor {
        let offset = max(0.004, rect.height * 0.16)
        let points = [
            CGPoint(x: rect.minX + rect.width * 0.2, y: rect.maxY + offset),
            CGPoint(x: rect.midX, y: rect.maxY + offset),
            CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.maxY + offset),
            CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY - offset),
            CGPoint(x: rect.midX, y: rect.minY - offset),
            CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.minY - offset),
            CGPoint(x: rect.minX - offset, y: rect.midY),
            CGPoint(x: rect.maxX + offset, y: rect.midY)
        ].map(sample)
        return OCRBackgroundColor(
            red: median(points.map(\.red)),
            green: median(points.map(\.green)),
            blue: median(points.map(\.blue))
        )
    }

    private func sample(_ point: CGPoint) -> OCRBackgroundColor {
        let normalizedX = min(max(point.x, 0), 0.999_999)
        let normalizedY = min(max(point.y, 0), 0.999_999)
        let x = min(width - 1, max(0, Int(normalizedX * CGFloat(width))))
        let y = min(height - 1, max(0, Int((1 - normalizedY) * CGFloat(height))))
        let offset = (y * width + x) * 4
        return OCRBackgroundColor(
            red: Double(pixels[offset]) / 255,
            green: Double(pixels[offset + 1]) / 255,
            blue: Double(pixels[offset + 2]) / 255
        )
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
