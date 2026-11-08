import Foundation
import SwiftData
import Photos
import Observation

/// Drives the Organise mode: step through photos and file each into one or more
/// Photos albums (existing or newly created). Album additions are applied to the
/// library immediately; advancing with "Next" marks the asset organised so it
/// won't resurface in future organise sessions.
@Observable
@MainActor
final class OrganiseSession {

    let assets: [PHAsset]
    var index: Int = 0 {
        didSet { loadMembership() }
    }
    /// Albums available to file into (mutable so newly created ones appear).
    private(set) var albums: [PHAssetCollection]

    /// assetLocalID -> set of album localIdentifiers the photo is in: the
    /// albums it was already in when it came up, plus any added this session.
    private(set) var added: [String: Set<String>] = [:]

    private let context: ModelContext
    private let library = PhotoLibraryService.shared

    init(assets: [PHAsset], albums: [PHAssetCollection], context: ModelContext) {
        self.assets = assets
        self.albums = albums
        self.context = context
        loadMembership()
    }

    /// Ticks the albums the current photo (and the next, so it's ready) is
    /// already in, read from Photos once per photo.
    private func loadMembership() {
        for i in [index, index + 1] where assets.indices.contains(i) {
            let asset = assets[i]
            guard added[asset.localIdentifier] == nil else { continue }
            let found = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
            var ids = Set<String>()
            found.enumerateObjects { collection, _, _ in ids.insert(collection.localIdentifier) }
            added[asset.localIdentifier] = ids
        }
    }

    var isComplete: Bool { index >= assets.count }
    var current: PHAsset? { assets.indices.contains(index) ? assets[index] : nil }
    var progress: Double { assets.isEmpty ? 1 : Double(index) / Double(assets.count) }
    var organisedCount: Int { index }

    func isAdded(album: PHAssetCollection, to asset: PHAsset) -> Bool {
        added[asset.localIdentifier]?.contains(album.localIdentifier) ?? false
    }

    /// Add the current asset to an existing album (idempotent per session).
    func add(_ asset: PHAsset, to album: PHAssetCollection) async {
        guard !isAdded(album: album, to: asset) else { return }
        let ok = await library.addAssets([asset], to: album)
        if ok {
            added[asset.localIdentifier, default: []].insert(album.localIdentifier)
        }
    }

    /// Create a new album, add the asset, and make it available for later photos.
    /// A name already in use files into that album rather than making its twin.
    func createAlbumAndAdd(name: String, asset: PHAsset) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let same = AlbumList.existing(named: trimmed, in: albums, title: \.localizedTitle) {
            await add(asset, to: same)
            return
        }
        guard let album = await library.createAlbum(named: trimmed) else { return }
        albums.append(album)
        albums.sort { ($0.localizedTitle ?? "").localizedStandardCompare($1.localizedTitle ?? "") == .orderedAscending }
        await add(asset, to: album)
    }

    /// Advance, marking the current asset organised so it's skipped next time.
    func next() {
        if let asset = current { markOrganised(asset.localIdentifier) }
        index += 1
    }

    /// Advance without marking (revisit later).
    func skip() { index += 1 }

    // MARK: - Persistence

    private func markOrganised(_ id: String) {
        var descriptor = FetchDescriptor<AssetReview>(predicate: #Predicate { $0.assetLocalID == id })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.organised = true
        } else {
            context.insert(AssetReview(assetLocalID: id, decision: .undecided, organised: true))
        }
        try? context.save()
    }
}
