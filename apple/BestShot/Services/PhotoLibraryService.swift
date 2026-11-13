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

    /// User-visible albums (non-smart, in folders or not), for the organise picker.
    /// One per name in each folder: the fullest stands for the others, which stay
    /// in Photos untouched.
    func userAlbums() -> [PHAssetCollection] { userAlbumsWithFolders().albums }

    /// The albums, and the folder each one sits in, by album id. Albums at the top
    /// level have none. Photos hides an album inside its folder, so the name of
    /// the folder is what tells "Lisbon" from "Lisbon" in Imported from Google.
    func userAlbumsWithFolders() -> (albums: [PHAssetCollection], folders: [String: String]) {
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var albums: [PHAssetCollection] = []
        result.enumerateObjects { collection, _, _ in albums.append(collection) }
        let folders = folderNames(albums)
        let unique = AlbumList.unique(albums, title: \.localizedTitle, count: \.estimatedAssetCount,
                                      folder: { folders[$0.localIdentifier] })
        return (unique, folders)
    }

    /// The nearest folder of each album that's in one.
    func folderNames(_ albums: [PHAssetCollection]) -> [String: String] {
        var folders: [String: String] = [:]
        for album in albums {
            let lists = PHCollectionList.fetchCollectionListsContaining(album, options: nil)
            if let name = lists.firstObject?.localizedTitle, !name.isEmpty {
                folders[album.localIdentifier] = name
            }
        }
        return folders
    }

    /// How many photos (not videos) each album holds, by album id: what Triage
    /// and Organise would go through. Slow with hundreds of albums, so call it
    /// off the main thread.
    func photoCounts(_ albums: [PHAssetCollection]) -> [String: Int] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        var counts: [String: Int] = [:]
        for album in albums {
            counts[album.localIdentifier] = PHAsset.fetchAssets(in: album, options: options).count
        }
        return counts
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
    func startCaching(_ assets: [PHAsset], targetSize: CGSize, contentMode: PHImageContentMode = .aspectFill) {
        imageManager.startCachingImages(for: assets, targetSize: targetSize,
                                        contentMode: contentMode, options: nil)
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

    /// Take assets out of an album. They stay in the library.
    func removeAssets(_ assets: [PHAsset], from collection: PHAssetCollection) async -> Bool {
        await performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
            request.removeAssets(assets as NSArray)
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

    /// Adds a finished file (a Tools export) to the library as a new photo or
    /// video. Asks only for add access, so it works without full library access.
    func saveFile(_ url: URL, isVideo: Bool) async -> Bool {
        let status = await withCheckedContinuation { cont in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { cont.resume(returning: $0) }
        }
        guard status == .authorized || status == .limited else { return false }
        return await performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: isVideo ? .video : .photo, fileURL: url, options: nil)
        }
    }

    /// Adds a photo file from Files to the library and returns the new photo.
    /// The file is copied first under coordinated access, which brings it down
    /// from iCloud if it isn't on the device yet; the original isn't changed.
    func importPhoto(from url: URL) async -> PHAsset? {
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(url.lastPathComponent)
        let copied = await Task.detached { Self.coordinatedCopy(url, to: copy) }.value
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        guard copied else { return nil }
        var placeholder: PHObjectPlaceholder?
        let ok = await performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = url.lastPathComponent
            request.addResource(with: .photo, fileURL: copy, options: options)
            placeholder = request.placeholderForCreatedAsset
        }
        guard ok, let id = placeholder?.localIdentifier else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    static func coordinatedCopy(_ source: URL, to destination: URL) -> Bool {
        let fm = FileManager.default
        guard (try? fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)) != nil
        else { return false }
        var error: NSError?
        var ok = false
        NSFileCoordinator().coordinate(readingItemAt: source, options: [.withoutChanges], error: &error) { readable in
            ok = (try? fm.copyItem(at: readable, to: destination)) != nil
        }
        return ok && error == nil
    }

    private func performChanges(_ changes: @escaping () -> Void) async -> Bool {
        await withCheckedContinuation { cont in
            PHPhotoLibrary.shared().performChanges(changes) { success, _ in
                cont.resume(returning: success)
            }
        }
    }
}
