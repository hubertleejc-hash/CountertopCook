import Foundation
import Vision
import CoreGraphics
import ImageIO
import CookCore

/// Reads the text in photos of a recipe: a cookbook page, a recipe card, a handwritten note, or
/// screenshots of a recipe shown in a video or a post. Apple's on-device text recognition
/// (Vision) does the reading, so nothing leaves the phone. The text goes on to the same reader
/// as pasted text, and then to the review screen: nothing is saved here.
/// Also built into the share extension, so a screenshot shared to Hearth is read the same way.
enum PhotoText {
    enum Failure: LocalizedError {
        case notAnImage
        case noText

        var errorDescription: String? {
            switch self {
            case .notAnImage: return "Couldn't open that photo. Try another one."
            case .noText: return "No text could be read in the photo. Try a sharper, closer photo of the recipe, in good light."
            }
        }
    }

    /// The text of every picture, in the order given, one after another.
    static func text(inImageData pictures: [Data], maxPixel: Int = 3000) async throws -> String {
        var images: [CGImage] = []
        for data in pictures {
            // Upright and big enough for small print, without decoding a 48 MP photo whole.
            guard let image = upright(data, maxPixel: maxPixel) else { throw Failure.notAnImage }
            images.append(image)
        }
        return try await text(in: images)
    }

    static func upright(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func text(in images: [CGImage]) async throws -> String {
        var pages: [String] = []
        for image in images {
            let page = try await Task.detached(priority: .userInitiated) { try read(image) }.value
            if !page.isEmpty { pages.append(page) }
        }
        guard !pages.isEmpty else { throw Failure.noText }
        return pages.joined(separator: "\n")
    }

    // MARK: Reading one picture

    private static func read(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Chinese and English recipes; the Chinese models read English too.
        let wanted = ["zh-Hans", "zh-Hant", "en-US"]
        if let supported = try? request.supportedRecognitionLanguages() {
            let languages = wanted.filter { supported.contains($0) }
            if !languages.isEmpty { request.recognitionLanguages = languages }
        }
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        let size = CGSize(width: image.width, height: image.height)
        let boxes = (request.results ?? []).flatMap { pieces(of: $0, in: size) }
        return TextLayout.readingOrder(boxes)
    }

    /// The observation as boxes in pixels (origin top left). A line the recogniser read across
    /// a wide gap ("鸡胸肉 2块      鲜面条 300g", or the titles of two step panels side by side)
    /// is cut at the gap, so the layout reader can tell the columns apart.
    private static func pieces(of observation: VNRecognizedTextObservation, in size: CGSize) -> [TextLayout.Box] {
        guard let candidate = observation.topCandidates(1).first else { return [] }
        let text = candidate.string
        func pixels(_ box: CGRect) -> CGRect {
            CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height,
                   width: box.width * size.width, height: box.height * size.height)
        }
        let whole = pixels(observation.boundingBox)
        // Words (runs between spaces) and where each one sits.
        var words: [(text: String, rect: CGRect)] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard let start = text[index...].firstIndex(where: { !$0.isWhitespace }) else { break }
            let end = text[start...].firstIndex(where: { $0.isWhitespace }) ?? text.endIndex
            if let box = try? candidate.boundingBox(for: start..<end)?.boundingBox {
                words.append((String(text[start..<end]), pixels(box)))
            } else {
                return [TextLayout.Box(text: text, rect: whole)]
            }
            index = end
        }
        guard words.count > 1 else { return [TextLayout.Box(text: text, rect: whole)] }
        var result: [TextLayout.Box] = []
        var current = TextLayout.Box(text: words[0].text, rect: words[0].rect)
        for word in words.dropFirst() {
            if word.rect.minX - current.rect.maxX > whole.height * 1.1 {
                result.append(current)
                current = TextLayout.Box(text: word.text, rect: word.rect)
            } else {
                current.text += " " + word.text
                current.rect = current.rect.union(word.rect)
            }
        }
        result.append(current)
        return result.map { TextLayout.Box(text: $0.text, rect: CGRect(x: $0.rect.minX, y: whole.minY,
                                                                      width: $0.rect.width, height: whole.height)) }
    }
}
