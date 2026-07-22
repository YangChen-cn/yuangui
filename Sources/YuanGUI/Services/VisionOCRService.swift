import CoreGraphics
import Foundation
import NaturalLanguage
import Vision

struct OCRBackgroundColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    /// Normalized color variation around the text. Values near zero describe a flat background.
    let variation: Double

    static let white = OCRBackgroundColor(red: 1, green: 1, blue: 1, variation: 0)

    init(red: Double, green: Double, blue: Double, variation: Double = 0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.variation = variation
    }

    var isDark: Bool {
        red * 0.2126 + green * 0.7152 + blue * 0.0722 < 0.48
    }
}

struct OCRTextRegion: Equatable, Sendable {
    let text: String
    /// Vision coordinates: normalized to 0...1 with the origin at bottom-left.
    let normalizedRect: CGRect
    let backgroundColor: OCRBackgroundColor
    let confidence: Float
    let detectedLanguage: String?
    let estimatedFontScale: CGFloat
    let paragraphIndex: Int
    let readingOrder: Int
    let isProtectedText: Bool

    init(
        text: String,
        normalizedRect: CGRect,
        backgroundColor: OCRBackgroundColor = .white,
        confidence: Float = 1,
        detectedLanguage: String? = nil,
        estimatedFontScale: CGFloat? = nil,
        paragraphIndex: Int = 0,
        readingOrder: Int = 0,
        isProtectedText: Bool? = nil
    ) {
        self.text = text
        self.normalizedRect = normalizedRect
        self.backgroundColor = backgroundColor
        self.confidence = confidence
        self.detectedLanguage = detectedLanguage
        self.estimatedFontScale = estimatedFontScale ?? normalizedRect.height
        self.paragraphIndex = paragraphIndex
        self.readingOrder = readingOrder
        self.isProtectedText = isProtectedText ?? Self.protectedText(text)
    }

    func assigningLayout(paragraphIndex: Int, readingOrder: Int) -> OCRTextRegion {
        OCRTextRegion(
            text: text,
            normalizedRect: normalizedRect,
            backgroundColor: backgroundColor,
            confidence: confidence,
            detectedLanguage: detectedLanguage,
            estimatedFontScale: estimatedFontScale,
            paragraphIndex: paragraphIndex,
            readingOrder: readingOrder,
            isProtectedText: isProtectedText
        )
    }

    private static func protectedText(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: #"(?:https?://|www\.)\S+|[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}"#, options: .regularExpression) != nil {
            return true
        }
        let meaningful = value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        guard !meaningful.isEmpty else { return true }
        let digits = meaningful.filter { CharacterSet.decimalDigits.contains($0) }
        return Double(digits.count) / Double(meaningful.count) > 0.8
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
    private static let maximumOCRPixelCount = 8_000_000
    private static let maximumOCRDimension = 3_200

    func recognizeText(in image: CGImage) async throws -> String {
        try await recognizeLayout(in: image).text
    }

    func recognizeLayout(in image: CGImage) async throws -> OCRRecognition {
        try await TranslationPerformance.measure(.ocr) {
            try await Task.detached(priority: .userInitiated) {
            let recognitionImage = Self.imageForRecognition(image)
            let backgroundSampler = ImageBackgroundSampler(image: recognitionImage)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            let preferredLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
            if let supported = try? request.supportedRecognitionLanguages() {
                request.recognitionLanguages = preferredLanguages.filter(supported.contains)
            }

            do {
                try VNImageRequestHandler(cgImage: recognitionImage, options: [:]).perform([request])
            } catch {
                throw VisionOCRError.recognitionFailed(error.localizedDescription)
            }

            let rawRegions = (request.results ?? [])
                .compactMap { observation -> OCRTextRegion? in
                    guard let candidate = observation.topCandidates(1).first,
                          !candidate.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    return OCRTextRegion(
                        text: text,
                        normalizedRect: observation.boundingBox,
                        backgroundColor: backgroundSampler?.color(around: observation.boundingBox) ?? .white,
                        confidence: candidate.confidence,
                        detectedLanguage: NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue,
                        estimatedFontScale: observation.boundingBox.height
                    )
                }
            return await TranslationPerformance.measure(.grouping) {
                OCRLayoutAnalyzer.organize(rawRegions)
            }
        }.value
        }
    }

    private static func imageForRecognition(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        let pixelCount = width * height
        guard width > maximumOCRDimension || height > maximumOCRDimension || pixelCount > maximumOCRPixelCount else {
            return image
        }
        let dimensionScale = min(
            Double(maximumOCRDimension) / Double(max(width, height)),
            sqrt(Double(maximumOCRPixelCount) / Double(max(1, pixelCount)))
        )
        let targetWidth = max(1, Int((Double(width) * dimensionScale).rounded()))
        let targetHeight = max(1, Int((Double(height) * dimensionScale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage() ?? image
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
        let red = median(points.map(\.red))
        let green = median(points.map(\.green))
        let blue = median(points.map(\.blue))
        let distances = points.map { sample in
            sqrt(pow(sample.red - red, 2) + pow(sample.green - green, 2) + pow(sample.blue - blue, 2))
        }
        return OCRBackgroundColor(red: red, green: green, blue: blue, variation: median(distances))
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
