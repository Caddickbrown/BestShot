import Foundation
import ImageIO
import AVFoundation
import UniformTypeIdentifiers
import CoreGraphics

/// Generates compact thumbnails for images and videos. Thumbnails are encoded
/// as HEIC (falling back to JPEG) and written by `MediaStore`.
enum ThumbnailService {

    /// Target longest edge for a thumbnail, in pixels.
    static let maxPixel: CGFloat = 512

    /// Build thumbnail data for image bytes, or nil on failure.
    static func imageThumbnail(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return encode(cg)
    }

    /// Build thumbnail data for a video file at `url` (first playable frame).
    static func videoThumbnail(url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        do {
            let time = CMTime(seconds: 0.1, preferredTimescale: 600)
            let cg = try await generator.image(at: time).image
            return encode(cg)
        } catch {
            return nil
        }
    }

    // MARK: - Encoding

    private static func encode(_ cg: CGImage) -> Data? {
        if let heic = encode(cg, as: UTType.heic.identifier) { return heic }
        return encode(cg, as: UTType.jpeg.identifier)
    }

    private static func encode(_ cg: CGImage, as typeIdentifier: String) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, typeIdentifier as CFString, 1, nil) else {
            return nil
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.7]
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
