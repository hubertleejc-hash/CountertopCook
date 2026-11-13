import Foundation
import Vision
import CoreGraphics
import ImageIO

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

    private struct Line {
        let text: String
        let box: CGRect   // Vision's normalised box: origin bottom-left, 0…1.
    }

    private static func read(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        let lines: [Line] = (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces),
                  !text.isEmpty else { return nil }
            return Line(text: text, box: observation.boundingBox)
        }
        return arrange(lines)
    }

    /// Puts the lines in reading order. A page in two columns (ingredients on the left, method on
    /// the right, as many recipe cards are laid out) is read one column after the other rather
    /// than across both, so the two lists don't get mixed up line by line.
    private static func arrange(_ lines: [Line]) -> String {
        guard !lines.isEmpty else { return "" }
        if let split = columnSplit(lines) {
            // A title across the top of both columns comes first.
            let header = lines.filter { crosses($0, split) }
            let body = lines.filter { !crosses($0, split) }
            let left = body.filter { $0.box.midX < split }
            let right = body.filter { $0.box.midX >= split }
            return [rows(header), rows(left), rows(right)].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        return rows(lines)
    }

    /// Top to bottom; pieces at the same height (an amount and its ingredient, read as two
    /// boxes) are joined left to right into one line.
    private static func rows(_ lines: [Line]) -> String {
        let sorted = lines.sorted { $0.box.midY > $1.box.midY }
        var rows: [[Line]] = []
        for line in sorted {
            if let last = rows.last?.last, abs(last.box.midY - line.box.midY) < min(last.box.height, line.box.height) * 0.5 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }

    private static func crosses(_ line: Line, _ x: CGFloat) -> Bool { line.box.minX < x && line.box.maxX > x }

    /// An x position in the middle of the page that no line crosses (apart from up to three
    /// title lines above everything else), with at least three lines on each side; nil for a
    /// page in one column.
    private static func columnSplit(_ lines: [Line]) -> CGFloat? {
        var best: (x: CGFloat, gap: CGFloat)?
        for step in 30...70 {
            let x = CGFloat(step) / 100
            let header = lines.filter { crosses($0, x) }
            let body = lines.filter { !crosses($0, x) }
            guard header.count <= 3 else { continue }
            if let lowestHeader = header.map(\.box.minY).min(), let topOfBody = body.map(\.box.maxY).max(),
               lowestHeader < topOfBody { continue }
            let left = body.filter { $0.box.maxX <= x }
            let right = body.filter { $0.box.minX >= x }
            guard left.count >= 3, right.count >= 3 else { continue }
            // Prefer the middle of the widest clear band.
            let leftEdge = left.map(\.box.maxX).max() ?? x
            let rightEdge = right.map(\.box.minX).min() ?? x
            let gap = rightEdge - leftEdge
            if gap > (best?.gap ?? 0.02) { best = ((leftEdge + rightEdge) / 2, gap) }
        }
        return best?.x
    }
}
