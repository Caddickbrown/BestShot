import SwiftUI
import Photos

/// Asynchronously loads and displays a Photos-library asset via
/// `PhotoLibraryService`, showing a placeholder while loading. Used by both the
/// triage card (large) and the session gallery (thumbnails).
struct PhotoAssetImage: View {
    let asset: PHAsset
    var targetSize: CGSize = CGSize(width: 1200, height: 1200)
    var contentMode: ContentMode = .fit

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
        .task(id: asset.localIdentifier) {
            image = nil
            image = await PhotoLibraryService.shared.requestImage(for: asset, targetSize: targetSize)
        }
    }
}
