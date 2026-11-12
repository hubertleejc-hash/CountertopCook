import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Recipe photos: shrunk to a sensible size when added, and decoded once for display.
enum PhotoStore {
    /// Longest side of a stored photo, in pixels.
    static let maxPixel = 1600

    /// A JPEG of the picked image, turned upright and no larger than `maxPixel`; nil when the
    /// data isn't an image.
    static func jpeg(from data: Data) -> Data? {
        guard let image = thumbnail(of: data, maxPixel: maxPixel) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private final class Box { let image: CGImage; init(_ image: CGImage) { self.image = image } }
    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 60
        return cache
    }()

    /// The photo decoded for the screen, at most `maxPixel` on its long side. Kept in memory so
    /// scrolling the shelf doesn't decode the same cover again and again.
    static func image(for photo: RecipePhoto, maxPixel: Int) -> CGImage? {
        let key = "\(photo.persistentModelID.hashValue)-\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit.image }
        guard let image = thumbnail(of: photo.data, maxPixel: maxPixel) else { return nil }
        cache.setObject(Box(image), forKey: key)
        return image
    }

    /// Picture data decoded for the screen, not cached (the review screen's one photo).
    static func image(of data: Data, maxPixel: Int) -> CGImage? { thumbnail(of: data, maxPixel: maxPixel) }

    private static func thumbnail(of data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// A recipe photo filling whatever frame it is given.
struct PhotoImage: View {
    let photo: RecipePhoto
    var maxPixel = 1200

    var body: some View {
        Theme.beige
            .overlay {
                if let image = PhotoStore.image(for: photo, maxPixel: maxPixel) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
    }
}
