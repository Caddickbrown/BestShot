import Foundation
import Photos
import CoreGraphics

/// Wraps PhotoKit: authorization, fetching assets, loading images, and the
/// mutating actions used by triage/organise (favourite, batch delete, add to
/// album, create album). All library mutations go through
/// `PHPhotoLibrary.performChanges`.
///
/// Not main-actor isolated: PhotoKit's fetch, image, and change APIs are
/// thread-safe, so this can be called from background tasks. The type holds no
/// mutable state of its own (`PHCachingImageManager` is thread-safe), hence
/// `@unchecked Sendable`.
final class PhotoLibraryService: @unchecked Sendable {
    static let shared = PhotoLibraryService()

    private let imageManager = PHCachingImageManager()

    private init() {}

    // MARK: - Authorization

    var status: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    var isAuthorized: Bool {
        let s = status
        return s == .authorized || s == .limited
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { cont in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                cont.resume(returning: status)
            }
        }
    }

    // MARK: - Fetching

    /// Fetch image assets, optionally scoped to a collection, ordered, and with
    /// already-reviewed local IDs removed.
    func fetchAssets(
        in collection: PHAssetCollection? = nil,
        order: SessionOrder,
        excluding reviewedIDs: Set<String>
    ) -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        if order != .random {
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: order == .oldest)]
        }

        let result: PHFetchResult<PHAsset>
        if let collection {
            result = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            result = PHAsset.fetchAssets(with: options)
        }

        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            if !reviewedIDs.contains(asset.localIdentifier) {
                assets.append(asset)
            }
        }
        if order == .random {
            assets.shuffle()
        }
        return assets
    }

    /// User-visible albums (top-level, non-smart), for the organise picker.
    func userAlbums() -> [PHAssetCollection] {
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var albums: [PHAssetCollection] = []
        result.enumerateObjects { collection, _, _ in albums.append(collection) }
        return albums.sorted { ($0.localizedTitle ?? "") .localizedStandardCompare($1.localizedTitle ?? "") == .orderedAscending }
    }

    /// Count of assets in a collection (for album chips).
    func assetCount(in collection: PHAssetCollection) -> Int {
        PHAsset.fetchAssets(in: collection, options: nil).count
    }

    // MARK: - Image loading

    /// Load a display image for an asset at the given pixel size.
    /// Uses `.highQualityFormat` so the handler fires exactly once.
    func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode = .aspectFit) async -> PlatformImage? {
        await withCheckedContinuation { cont in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, _ in
                cont.resume(returning: image)
            }
        }
    }

    /// Start caching thumbnails for a batch of assets (grid performance).
    func startCaching(_ assets: [PHAsset], targetSize: CGSize) {
        imageManager.startCachingImages(for: assets, targetSize: targetSize,
                                        contentMode: .aspectFill, options: nil)
    }

    func stopCachingAll() {
        imageManager.stopCachingImagesForAllAssets()
    }

    // MARK: - Mutations

    /// Favourite / unfavourite an asset (no system prompt with read-write access).
    func setFavorite(_ favorite: Bool, for asset: PHAsset) async -> Bool {
        await performChanges {
            let request = PHAssetChangeRequest(for: asset)
            request.isFavorite = favorite
        }
    }

    /// Batch-delete assets. iOS/macOS shows ONE system confirmation for the set;
    /// deleted assets go to Recently Deleted. Returns true if the user confirmed.
    func deleteAssets(_ assets: [PHAsset]) async -> Bool {
        guard !assets.isEmpty else { return true }
        return await performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    /// Add assets to an existing album.
    func addAssets(_ assets: [PHAsset], to collection: PHAssetCollection) async -> Bool {
        await performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
            request.addAssets(assets as NSArray)
        }
    }

    /// Create a new album and return it (or nil on failure).
    func createAlbum(named title: String) async -> PHAssetCollection? {
        var placeholder: PHObjectPlaceholder?
        let ok = await performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            placeholder = request.placeholderForCreatedAssetCollection
        }
        guard ok, let id = placeholder?.localIdentifier else { return nil }
        let result = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
        return result.firstObject
    }

    /// Makes the album titled `title` (created if needed) contain exactly
    /// `assets`, in that order, so Photos shows a ranking best-first.
    func replaceAlbumContents(titled title: String, with assets: [PHAsset]) async -> Bool {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title == %@", title)
        var album = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject
        if album == nil {
            album = await createAlbum(named: title)
        }
        guard let album else { return false }
        let existing = PHAsset.fetchAssets(in: album, options: nil)
        return await performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: album, assets: existing) else { return }
            if existing.count > 0 {
                request.removeAssets(existing)
            }
            request.insertAssets(assets as NSArray, at: IndexSet(integersIn: 0..<assets.count))
        }
    }

    // MARK: - Helper

    private func performChanges(_ changes: @escaping () -> Void) async -> Bool {
        await withCheckedContinuation { cont in
            PHPhotoLibrary.shared().performChanges(changes) { success, _ in
                cont.resume(returning: success)
            }
        }
    }
}
