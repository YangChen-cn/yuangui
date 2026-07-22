import CoreGraphics
import Foundation
import Vision

protocol OCRTextRecognizing: Sendable {
    func recognizeText(in image: CGImage) async throws -> String
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
        try await Task.detached(priority: .userInitiated) {
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

            return (request.results ?? [])
                .sorted(by: Self.isBeforeInReadingOrder)
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
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
