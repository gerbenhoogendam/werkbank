import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Screenshots voor verbeteringen: verkleind tot een breedte die Claude goed leest, als JPEG (klein genoeg voor iCloud).
enum ScreenshotEncoding {
    static func jpeg(_ image: CGImage, maxWidth: Int = 1800, quality: Double = 0.72) -> Data? {
        let scaled = scale(image, maxWidth: maxWidth) ?? image
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    static func image(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Een klein voorbeeld voor in de lijst.
    static func thumbnail(_ data: Data, maxPixels: Int = 240) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func scale(_ image: CGImage, maxWidth: Int) -> CGImage? {
        guard image.width > maxWidth else { return nil }
        let height = Int((Double(image.height) * Double(maxWidth) / Double(image.width)).rounded())
        guard let context = CGContext(data: nil, width: maxWidth, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: height))
        return context.makeImage()
    }
}
