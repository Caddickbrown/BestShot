import Foundation
import SwiftData
import Photos
import Observation
import UniformTypeIdentifiers

/// One thing to file: a photo in the library, or a photo file in a folder
/// chosen in Files (iCloud Drive, a camera import). A file joins the library
/// only when it's first filed into an album.
enum OrganiseItem: Equatable {
    case asset(PHAsset)
    case file(URL)

    var id: String {
        switch self {
        case .asset(let asset): return asset.localIdentifier
        case .file(let url): return "file:" + url.standardizedFileURL.path
        }
    }

    var name: String? {
        if case .file(let url) = self { return url.lastPathComponent }
        return nil
    }
}

/// Drives the Organise mode: step through photos and file each into one or more
/// Photos albums (existing or newly created). Album additions are applied to the
/// library immediately; advancing with "Next" marks the asset organised so it
/// won't resurface in future organise sessions.
@Observable
@MainActor
final class OrganiseSession {

    let items: [OrganiseItem]
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

    /// item id -> set of album localIdentifiers the photo is in: the
    /// albums it was already in when it came up, plus any added this session.
    private(set) var added: [String: Set<String>] = [:]
    /// A file's photo in the library, once it's been filed somewhere.
    private var imported: [String: PHAsset] = [:]
    /// Why the last file couldn't be added to the library.
    var problem: String?

    /// The folder chosen in Files, kept open while the session runs.
    private let scopedFolder: URL?
    /// The folder's name, for the header.
    let folderName: String?

    private let context: ModelContext
    private let library = PhotoLibraryService.shared

    init(assets: [PHAsset], albums: [PHAssetCollection], folders: [String: String] = [:], context: ModelContext) {
        self.items = assets.map(OrganiseItem.asset)
        self.albums = AlbumRecency.ordered(albums)
        self.folders = folders
        self.context = context
        self.scopedFolder = nil
        self.folderName = nil
        loadMembership()
    }

    /// Photo files from a folder in Files. `folder` is security-scoped and its
    /// access already started; the session stops it when it ends.
    init(files: [URL], folder: URL, albums: [PHAssetCollection], folders: [String: String] = [:], context: ModelContext) {
        self.items = files.map(OrganiseItem.file)
        self.albums = AlbumRecency.ordered(albums)
        self.folders = folders
        self.context = context
        self.scopedFolder = folder
        self.folderName = folder.lastPathComponent
        loadMembership()
    }

    deinit {
        scopedFolder?.stopAccessingSecurityScopedResource()
    }

    /// Ticks the albums the current photo (and the next, so it's ready) is
    /// already in, read from Photos once per photo. A file not yet in the
    /// library is in none.
    private func loadMembership() {
        for i in [index, index + 1] where items.indices.contains(i) {
            let item = items[i]
            guard added[item.id] == nil else { continue }
            guard case .asset(let asset) = item else {
                added[item.id] = []
                continue
            }
            let found = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
            var ids = Set<String>()
            found.enumerateObjects { collection, _, _ in ids.insert(collection.localIdentifier) }
            added[item.id] = ids
        }
    }

    var isComplete: Bool { index >= items.count }
    var currentItem: OrganiseItem? { items.indices.contains(index) ? items[index] : nil }
    /// The current photo in the library: the photo itself, or a file's once filed.
    var current: PHAsset? {
        switch currentItem {
        case .asset(let asset): return asset
        case .file: return currentItem.flatMap { imported[$0.id] }
        case nil: return nil
        }
    }
    var progress: Double { items.isEmpty ? 1 : Double(index) / Double(items.count) }
    var organisedCount: Int { index }
    var fromFiles: Bool { scopedFolder != nil }

    /// The folder an album is in, if any.
    func folder(of album: PHAssetCollection) -> String? { folders[album.localIdentifier] }

    /// "Lisbon · Imported from Google", or the name alone at the top level.
    func label(_ album: PHAssetCollection) -> String {
        AlbumList.label(title: album.localizedTitle, folder: folder(of: album))
    }

    func isAdded(album: PHAssetCollection, to item: OrganiseItem) -> Bool {
        added[item.id]?.contains(album.localIdentifier) ?? false
    }

    func isAdded(album: PHAssetCollection, to asset: PHAsset) -> Bool {
        isAdded(album: album, to: .asset(asset))
    }

    /// The item's photo in the library, adding a file to it the first time.
    private func libraryAsset(for item: OrganiseItem) async -> PHAsset? {
        switch item {
        case .asset(let asset):
            return asset
        case .file(let url):
            if let done = imported[item.id] { return done }
            problem = nil
            guard let asset = await library.importPhoto(from: url) else {
                problem = "Couldn't add \(url.lastPathComponent) to your library."
                return nil
            }
            imported[item.id] = asset
            return asset
        }
    }

    /// Add the item to an existing album (idempotent per session).
    func add(_ item: OrganiseItem, to album: PHAssetCollection) async {
        guard !isAdded(album: album, to: item), let asset = await libraryAsset(for: item) else { return }
        let ok = await library.addAssets([asset], to: album)
        if ok {
            added[item.id, default: []].insert(album.localIdentifier)
            AlbumRecency.used(album.localIdentifier)
        }
    }

    func add(_ asset: PHAsset, to album: PHAssetCollection) async { await add(.asset(asset), to: album) }

    /// Take the photo out of an album (the photo itself stays in the library).
    func remove(_ item: OrganiseItem, from album: PHAssetCollection) async {
        guard isAdded(album: album, to: item) else { return }
        let asset: PHAsset?
        if case .asset(let a) = item { asset = a } else { asset = imported[item.id] }
        guard let asset else { return }
        let ok = await library.removeAssets([asset], from: album)
        if ok { added[item.id]?.remove(album.localIdentifier) }
    }

    /// Single album mode: one tap files the photo and moves straight on.
    /// Remembered on this device.
    var singleAlbum: Bool = UserDefaults.standard.bool(forKey: "organise.singleAlbum") {
        didSet { UserDefaults.standard.set(singleAlbum, forKey: "organise.singleAlbum") }
    }

    /// What a tap on an album does: in single album mode, file it and go to
    /// the next photo (after a beat, so the tick is seen); otherwise toggle.
    func pick(_ item: OrganiseItem, album: PHAssetCollection) async {
        guard singleAlbum else { await toggle(item, in: album); return }
        await add(item, to: album)
        guard isAdded(album: album, to: item) else { return }   // the add failed: stay put
        try? await Task.sleep(for: .milliseconds(250))
        if currentItem?.id == item.id { next() }
    }

    func pick(_ asset: PHAsset, album: PHAssetCollection) async { await pick(.asset(asset), album: album) }

    /// A tap on an album: in if it's out, out if it's in.
    func toggle(_ item: OrganiseItem, in album: PHAssetCollection) async {
        if isAdded(album: album, to: item) { await remove(item, from: album) }
        else { await add(item, to: album) }
    }

    /// Create a new album, add the asset, and make it available for later photos.
    /// A name already in use files into that album rather than making its twin.
    func createAlbumAndAdd(name: String, asset: PHAsset) async {
        await createAlbumAndAdd(name: name, item: .asset(asset))
    }

    func createAlbumAndAdd(name: String, item: OrganiseItem) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let same = AlbumList.existing(named: trimmed, in: albums, title: \.localizedTitle, folder: folder(of:)) {
            await pick(item, album: same)
            return
        }
        guard let album = await library.createAlbum(named: trimmed) else { return }
        // A new album joins the front of the pool at once, ready for the next photo.
        albums.insert(album, at: 0)
        await pick(item, album: album)
    }

    /// Advance, marking the current asset organised so it's skipped next time.
    func next() {
        if case .file(let url) = currentItem { OrganisedFiles.mark(url) }
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

/// Files from Files that Next has been pressed on, so they don't come up
/// again. Kept on this device, by path.
enum OrganisedFiles {
    private static let key = "organise.filesDone"
    private static let keep = 20_000

    static func key(for url: URL) -> String { url.standardizedFileURL.path }

    static var done: Set<String> {
        Set((UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]).keys)
    }

    static func mark(_ url: URL) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        all[key(for: url)] = Date().timeIntervalSince1970
        if all.count > keep {
            for (k, _) in all.sorted(by: { $0.value < $1.value }).prefix(all.count - keep) { all[k] = nil }
        }
        UserDefaults.standard.set(all, forKey: key)
    }
}

/// The photo files in a folder from Files and the folders inside it (a camera
/// import keeps them in DCIM/100APPLE and so on), oldest or newest first.
enum FolderPhotos {
    static func list(in folder: URL, order: SessionOrder, excluding done: Set<String> = []) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentTypeKey, .creationDateKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var found: [(url: URL, date: Date)] = []
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let type = values.contentType ?? UTType(filenameExtension: url.pathExtension),
                  type.conforms(to: .image),
                  !done.contains(OrganisedFiles.key(for: url))
            else { continue }
            found.append((url, values.creationDate ?? values.contentModificationDate ?? .distantPast))
        }
        switch order {
        case .random: found.shuffle()
        case .oldest: found.sort { ($0.date, $0.url.path) < ($1.date, $1.url.path) }
        case .newest: found.sort { ($0.date, $0.url.path) > ($1.date, $1.url.path) }
        }
        return found.map(\.url)
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

    /// The albums used most recently, newest first.
    static func recentIDs(_ limit: Int) -> [String] {
        stamps.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
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
