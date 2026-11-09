import CoreGraphics
import Foundation
import ImageIO
import KKitServicesAPI
import UniformTypeIdentifiers
import Vision

/// Encodes captured images. Runs off the main actor.
enum ImageEncoder {
    struct EncodingError: LocalizedError {
        var errorDescription: String? { String(localized: "Couldn't encode the screenshot.") }
    }

    /// The image as `format` data. HEIC and JPEG drop the alpha channel.
    static func encode(_ capture: CapturedImage, as format: ImageFormat, quality: Double) throws -> Data {
        try encode(capture.image, typeIdentifier: format.typeIdentifier, quality: quality, scale: capture.scale)
    }

    static func png(_ capture: CapturedImage) throws -> Data {
        try encode(capture.image, typeIdentifier: UTType.png.identifier, quality: 1, scale: capture.scale)
    }

    static func encode(_ image: CGImage, typeIdentifier: String, quality: Double, scale: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, typeIdentifier as CFString, 1, nil) else {
            throw EncodingError()
        }
        // 72 dpi × scale, so the file opens at its point size (like macOS screenshots).
        let dpi = 72 * scale
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw EncodingError() }
        return data as Data
    }
}

/// Text and barcode recognition with Vision, on-device.
enum ImageAnalyzer {
    /// Recognised lines, top to bottom. `language` is a Vision code ("en-US"); empty
    /// detects it.
    static func recognizeText(in capture: CapturedImage, language: String) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if language.isEmpty {
                request.automaticallyDetectsLanguage = true
            } else {
                request.recognitionLanguages = [language]
            }
            let handler = VNImageRequestHandler(cgImage: capture.image, options: [:])
            try handler.perform([request])
            let observations = request.results ?? []
            return observations
                .sorted { lhs, rhs in
                    // Vision's origin is bottom-left: higher boxes first, then left to right.
                    if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.01 {
                        return lhs.boundingBox.midY > rhs.boundingBox.midY
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }
                .compactMap { $0.topCandidates(1).first?.string }
        }.value
    }

    /// The payloads of every QR code and barcode in the image.
    static func detectCodes(in capture: CapturedImage) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: capture.image, options: [:])
            try handler.perform([request])
            var seen = Set<String>()
            return (request.results ?? []).compactMap { observation in
                guard let payload = observation.payloadStringValue, seen.insert(payload).inserted else { return nil }
                return payload
            }
        }.value
    }

    /// The languages text recognition knows, as Vision codes.
    static func supportedLanguages() -> [String] {
        (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? ["en-US"]
    }

    /// Joins recognised lines into text: lines stay lines.
    static func text(from lines: [String]) -> String {
        lines.joined(separator: "\n")
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}
