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
        didSet {
            loadMembership()
            albums = AlbumRecency.ordered(albums)   // reorder between photos, never under a finger
        }
    }
    /// Albums available to file into (mutable so newly created ones appear).
    private(set) var albums: [PHAssetCollection]
    /// Album id → the folder it's in, worked out once when the session starts.
    /// A new album is made at the top level, so it never has one.
    private let folders: [String: String]

    /// assetLocalID -> set of album localIdentifiers the photo is in: the
    /// albums it was already in when it came up, plus any added this session.
    private(set) var added: [String: Set<String>] = [:]

    private let context: ModelContext
    private let library = PhotoLibraryService.shared

    init(assets: [PHAsset], albums: [PHAssetCollection], folders: [String: String] = [:], context: ModelContext) {
        self.assets = assets
        self.albums = AlbumRecency.ordered(albums)
        self.folders = folders
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

    /// The folder an album is in, if any.
    func folder(of album: PHAssetCollection) -> String? { folders[album.localIdentifier] }

    /// "Lisbon · Imported from Google", or the name alone at the top level.
    func label(_ album: PHAssetCollection) -> String {
        AlbumList.label(title: album.localizedTitle, folder: folder(of: album))
    }

    func isAdded(album: PHAssetCollection, to asset: PHAsset) -> Bool {
        added[asset.localIdentifier]?.contains(album.localIdentifier) ?? false
    }

    /// Add the current asset to an existing album (idempotent per session).
    func add(_ asset: PHAsset, to album: PHAssetCollection) async {
        guard !isAdded(album: album, to: asset) else { return }
        let ok = await library.addAssets([asset], to: album)
        if ok {
            added[asset.localIdentifier, default: []].insert(album.localIdentifier)
            AlbumRecency.used(album.localIdentifier)
        }
    }

    /// Take the photo out of an album (the photo itself stays in the library).
    func remove(_ asset: PHAsset, from album: PHAssetCollection) async {
        guard isAdded(album: album, to: asset) else { return }
        let ok = await library.removeAssets([asset], from: album)
        if ok { added[asset.localIdentifier]?.remove(album.localIdentifier) }
    }

    /// Single album mode: one tap files the photo and moves straight on.
    /// Remembered on this device.
    var singleAlbum: Bool = UserDefaults.standard.bool(forKey: "organise.singleAlbum") {
        didSet { UserDefaults.standard.set(singleAlbum, forKey: "organise.singleAlbum") }
    }

    /// What a tap on an album does: in single album mode, file it and go to
    /// the next photo (after a beat, so the tick is seen); otherwise toggle.
    func pick(_ asset: PHAsset, album: PHAssetCollection) async {
        guard singleAlbum else { await toggle(asset, in: album); return }
        await add(asset, to: album)
        guard isAdded(album: album, to: asset) else { return }   // the add failed: stay put
        try? await Task.sleep(for: .milliseconds(250))
        if current?.localIdentifier == asset.localIdentifier { next() }
    }

    /// A tap on an album: in if it's out, out if it's in.
    func toggle(_ asset: PHAsset, in album: PHAssetCollection) async {
        if isAdded(album: album, to: asset) { await remove(asset, from: album) }
        else { await add(asset, to: album) }
    }

    /// Create a new album, add the asset, and make it available for later photos.
    /// A name already in use files into that album rather than making its twin.
    func createAlbumAndAdd(name: String, asset: PHAsset) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let same = AlbumList.existing(named: trimmed, in: albums, title: \.localizedTitle, folder: folder(of:)) {
            await pick(asset, album: same)
            return
        }
        guard let album = await library.createAlbum(named: trimmed) else { return }
        // A new album joins the front of the pool at once, ready for the next photo.
        albums.insert(album, at: 0)
        await pick(asset, album: album)
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

/// Albums you've filed into most recently come first, so the ones in use
/// build up into a pool at the front; the rest follow A to Z. Kept on this
/// device between sessions.
enum AlbumRecency {
    private static let key = "organise.albumRecency"
    private static let keep = 200

    /// Album id → when it was last filed into.
    private static var stamps: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Albums this near the front stay where they are when used again, so
    /// the ones you're working with don't shuffle under your finger.
    static let settled = 5

    static func used(_ albumID: String) {
        var s = stamps
        let front = s.sorted { $0.value > $1.value }.prefix(settled).map(\.key)
        guard !front.contains(albumID) else { return }
        s[albumID] = Date().timeIntervalSince1970
        if s.count > keep {
            for (id, _) in s.sorted(by: { $0.value < $1.value }).prefix(s.count - keep) { s[id] = nil }
        }
        stamps = s
    }

    static func ordered(_ albums: [PHAssetCollection]) -> [PHAssetCollection] {
        let s = stamps
        return albums.sorted { a, b in
            switch (s[a.localIdentifier], s[b.localIdentifier]) {
            case let (x?, y?): return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil):
                return (a.localizedTitle ?? "").localizedStandardCompare(b.localizedTitle ?? "") == .orderedAscending
            }
        }
    }
}
