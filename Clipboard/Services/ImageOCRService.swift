import Foundation
import ImageIO
import Vision

enum ImageOCRServiceError: LocalizedError {
    case unsupportedImageData
    case noTextDetected

    var errorDescription: String? {
        switch self {
        case .unsupportedImageData:
            return "Unable to read this image for OCR."
        case .noTextDetected:
            return "No readable text found in this image."
        }
    }
}

/// Performs Vision-based OCR on image data in a background queue.
final class ImageOCRService {
    private let queue = DispatchQueue(label: "com.clipvault.ocr", qos: .userInitiated)

    func extractText(fromImageData imageData: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                autoreleasepool {
                    guard
                        let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                        let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
                    else {
                        continuation.resume(throwing: ImageOCRServiceError.unsupportedImageData)
                        return
                    }

                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    request.minimumTextHeight = 0.01

                    do {
                        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                        try handler.perform([request])

                        let observations = request.results as? [VNRecognizedTextObservation] ?? []
                        let recognizedText = observations
                            .compactMap { $0.topCandidates(1).first?.string }
                            .joined(separator: "\n")
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        guard !recognizedText.isEmpty else {
                            continuation.resume(throwing: ImageOCRServiceError.noTextDetected)
                            return
                        }

                        continuation.resume(returning: recognizedText)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
