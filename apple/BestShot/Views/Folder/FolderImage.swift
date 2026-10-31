import SwiftUI
import ImageIO

/// Decodes images straight from disk with ImageIO (HEIC included, EXIF
/// rotation applied), only as large as needed, cached by file and size.
actor FolderImageCache {
    static let shared = FolderImageCache()
    private let cache = NSCache<NSString, CGImageBox>()

    final class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    init() {
        cache.totalCostLimit = 512 * 1024 * 1024
    }

    func image(at url: URL, maxPixel: Int) -> CGImage? {
        let key = "\(maxPixel)|\(url.path)" as NSString
        if let hit = cache.object(forKey: key) { return hit.image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        cache.setObject(CGImageBox(image), forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }

    /// Warms the cache for images about to be shown.
    func preload(_ urls: [URL], maxPixel: Int) {
        for url in urls { _ = image(at: url, maxPixel: maxPixel) }
    }
}

/// An image file shown at up to `maxPixel` on its longest side.
struct FolderImage: View {
    let url: URL
    var maxPixel: Int = 480
    var contentMode: ContentMode = .fill

    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                Rectangle().fill(Theme.table.tile)
                    .overlay(Text(url.pathExtension.uppercased()).font(.mono(11)).foregroundStyle(Theme.table.muted))
            } else {
                Rectangle().fill(Theme.table.tile.opacity(0.4))
            }
        }
        .task(id: "\(maxPixel)|\(url.path)") {
            let loaded = await FolderImageCache.shared.image(at: url, maxPixel: maxPixel)
            image = loaded
            failed = loaded == nil
        }
    }
}
