import SwiftUI

/// Loads decoded images off the main actor with a small in-memory cache, keyed
/// by file URL. Used for both thumbnails and full-size viewer images.
actor ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, PlatformImage>()

    func image(at url: URL, downsampleTo maxPixel: CGFloat? = nil) -> PlatformImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let image: PlatformImage?
        if let maxPixel, let ds = ImageLoader.downsample(data: data, maxPixel: maxPixel) {
            image = ds
        } else {
            image = PlatformImage.fromData(data)
        }
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}

enum ImageLoader {
    static func downsample(data: Data, maxPixel: CGFloat) -> PlatformImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: cg)
        #else
        return NSImage(cgImage: cg, size: .init(width: cg.width, height: cg.height))
        #endif
    }
}

/// A view that asynchronously loads and displays an image from a file URL,
/// showing a placeholder while loading.
struct AsyncFileImage: View {
    let url: URL?
    var downsampleTo: CGFloat? = nil
    var contentMode: ContentMode = .fill

    @State private var image: PlatformImage?

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: url) {
            image = nil
            guard let url else { return }
            image = await ImageCache.shared.image(at: url, downsampleTo: downsampleTo)
        }
    }
}
