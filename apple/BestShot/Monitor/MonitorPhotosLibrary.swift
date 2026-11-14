import SwiftUI
import SwiftData
import Photos

/// The monitor's way to the real thing: the Triage session the phone is on, and
/// the same services and saved records the phone's screens use. The monitor adds
/// no way of its own to delete: `commitDeletions` is the session's.
@Observable
@MainActor
final class MonitorPhotosLibrary: MonitorLibrary {
    private let context: ModelContext
    private let triage = TriageHolder.shared
    private let photos = PhotoLibraryService.shared
    private let labels = LabelStore.shared
    private var access = PhotoLibraryService.shared.status
    private var albums: [PHAssetCollection] = []
    /// Filled in as photos are looked up, which a redraw mustn't trigger.
    @ObservationIgnored private var assets: [String: PHAsset] = [:]
    @ObservationIgnored private var idCache: (session: ObjectIdentifier, ids: [String])?
    private var organise: OrganiseSession?
    private var rankMedia = PhotosRankMedia()

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Photos access

    var hasPhotoAccess: Bool { access == .authorized || access == .limited }
    var canAskForPhotoAccess: Bool { access == .notDetermined }

    func askForPhotoAccess() async {
        access = await photos.requestAuthorization()
        reloadSources()
    }

    // MARK: Triage

    var triageIDs: [String] {
        guard let session = triage.session else { return [] }
        let key = ObjectIdentifier(session)
        if let idCache, idCache.session == key { return idCache.ids }
        let ids = session.assets.map(\.localIdentifier)
        idCache = (key, ids)
        return ids
    }

    var triageWaiting: Int { triage.session?.deleteCount ?? 0 }

    var triageIndex: Int {
        get { triage.session?.index ?? 0 }
        set { triage.session?.focus(on: newValue) }
    }

    private func asset(_ id: String) -> PHAsset? {
        if let known = assets[id] { return known }
        guard let found = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        assets[id] = found
        return found
    }

    func decision(_ id: String) -> ReviewDecision {
        guard let session = triage.session, let asset = asset(id) else { return .undecided }
        return session.decision(for: asset)
    }

    func setDecision(_ decision: ReviewDecision, _ id: String) {
        guard let asset = asset(id) else { return }
        triage.session?.setDecision(decision, for: asset)
    }

    func isFavourite(_ id: String) -> Bool {
        guard let session = triage.session, let asset = asset(id) else { return false }
        return session.isFavourited(asset)
    }

    func toggleFavourite() { triage.session?.toggleFavourite() }

    var sources: [(option: TriageSourceOption, title: String)] {
        TriageSourceOption.quick.map { ($0, $0.title) }
            + albums.map { (.album($0.localIdentifier), $0.localizedTitle ?? "Album") }
    }

    func reloadSources() {
        access = photos.status
        if hasPhotoAccess { albums = photos.userAlbums() }
    }

    func startTriage(order: SessionOrder, source: TriageSourceOption) async -> String? {
        guard triage.session == nil else { return nil }
        guard await HiddenGate.shared.allows(source) else { return "Hidden stays locked without Face ID." }
        let found = TriageHomeView.fetchSession(order: order, source: source, context: context)
        guard !found.isEmpty else {
            return "No unreviewed photos found for this source. Try another source or order."
        }
        assets = Dictionary(found.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        triage.paused = false
        triage.session = TriageSession(assets: found, context: context)
        return nil
    }

    func leaveTriage() { triage.leave() }
    func resumeTriage() { triage.paused = false }
    func commitDeletions() async -> Int { await triage.session?.commitDeletions() ?? 0 }
    func endTriage() { triage.end() }

    func details(_ id: String) -> [String] {
        guard let asset = asset(id) else { return [] }
        var lines = ["\(asset.pixelWidth) × \(asset.pixelHeight)"]
        if let date = asset.creationDate { lines.insert(date.formatted(date: .abbreviated, time: .shortened), at: 0) }
        if isFavourite(id) { lines.append("Favourite") }
        return lines
    }

    // MARK: Rank

    func rankBoard() async -> RankBoard? {
        guard hasPhotoAccess else { return nil }
        return PhotosRankView.makeBoard(context: context, media: rankMedia)
    }

    func saveRankAlbum(_ ids: [String]) async -> String {
        await PhotosRankView.saveAlbum(ids.compactMap { rankMedia.assets[$0] })
    }

    // MARK: Organise

    /// A file from Files isn't in Photos until it's filed, so it goes by the item.
    var organisePhoto: String? { organise?.currentItem?.id }

    var organiseProgress: String {
        guard let organise else { return "" }
        let count = "\(min(organise.index + 1, organise.items.count)) / \(organise.items.count)"
        let problem = organise.fromFiles ? organise.problem : nil
        return [count, organise.folderName, organise.currentItem?.name, problem].compactMap { $0 }.joined(separator: " · ")
    }

    var organiseAlbums: [(id: String, title: String, added: Bool)] {
        guard let organise, let current = organise.currentItem else { return [] }
        return organise.albums.map {
            ($0.localIdentifier, organise.label($0), organise.isAdded(album: $0, to: current))
        }
    }

    func startOrganise(order: SessionOrder, source: TriageSourceOption) async -> String? {
        guard await HiddenGate.shared.allows(source) else { return "Hidden stays locked without Face ID." }
        let found = OrganiseHomeView.fetchSession(order: order, source: source, context: context)
        guard !found.isEmpty else { return "No unorganised photos found for this source." }
        for asset in found { assets[asset.localIdentifier] = asset }
        let albums = photos.userAlbumsWithFolders()
        organise = OrganiseSession(assets: found, albums: albums.albums, folders: albums.folders, context: context)
        return nil
    }

    func startOrganise(folder: URL, order: SessionOrder) async -> String? {
        switch await OrganiseSession.fromFolder(folder, order: order, context: context) {
        case .success(let started):
            for case .file(let url) in started.items { files[OrganiseItem.file(url).id] = url }
            organise = started
            return nil
        case .failure(let problem):
            return problem.message
        }
    }

    /// Photo files from Files, by their item id, for their pictures.
    @ObservationIgnored private var files: [String: URL] = [:]

    func addToAlbum(_ id: String) async {
        guard let organise, let item = organise.currentItem,
              let album = organise.albums.first(where: { $0.localIdentifier == id }) else { return }
        await organise.pick(item, album: album)
    }

    func newAlbum(_ title: String) async {
        guard let organise, let item = organise.currentItem else { return }
        await organise.createAlbumAndAdd(name: title, item: item)
    }

    func nextOrganised() { organise?.next() }
    func skipOrganised() { organise?.skip() }

    /// Anything filed is filed already, and each step saves as it goes.
    func leaveOrganise() {
        if organise?.isComplete == true { organise = nil }
    }

    // MARK: Imported media

    var projects: [(id: UUID, name: String, count: Int)] {
        let all = (try? context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]))) ?? []
        return all.map { ($0.uuid, $0.name, $0.itemCount) }
    }

    @ObservationIgnored private var items: [String: URL] = [:]

    func media(project: UUID?) -> [MonitorMediaItem] {
        let all = (try? context.fetch(FetchDescriptor<MediaItem>(sortBy: [SortDescriptor(\.importedAt, order: .reverse)]))) ?? []
        let shown = project.map { id in all.filter { $0.project?.uuid == id } } ?? all
        for item in shown {
            items[item.uuid.uuidString] = item.thumbnailURL ?? item.fileURL
            fullSize[item.uuid.uuidString] = item.fileURL
        }
        return shown.map {
            MonitorMediaItem(id: $0.uuid.uuidString, title: $0.filename,
                             detail: ([$0.project?.name, $0.tags.isEmpty ? nil : $0.tags.joined(separator: ", ")]).compactMap { $0 }.joined(separator: " · "),
                             tags: $0.tags)
        }
    }

    @ObservationIgnored private var fullSize: [String: URL] = [:]

    // MARK: Settings

    func labelName(_ colour: LabelColour) -> String { labels.name(colour) }

    func renameLabel(_ colour: LabelColour, to name: String) -> String? {
        do {
            try labels.save(BestShot.renameLabel(settings: labels.settings, colour: colour, name: name))
            return nil
        } catch {
            return (error as? CoreError)?.message ?? error.localizedDescription
        }
    }

    var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: Pictures

    func picture(_ id: String, longEdge: CGFloat, fill: Bool) -> AnyView {
        if let url = files[id] ?? (longEdge > 500 ? fullSize[id] : items[id]) {
            return AnyView(AsyncFileImage(url: url, downsampleTo: longEdge, contentMode: fill ? .fill : .fit))
        }
        guard let asset = asset(id) else { return AnyView(Color.clear) }
        return AnyView(MonitorAssetImage(asset: asset, longEdge: longEdge, fill: fill))
    }

    func warm(_ ids: [String], longEdge: CGFloat) {
        photos.stopCachingAll()
        photos.startCaching(ids.compactMap(asset), targetSize: CGSize(width: longEdge, height: longEdge), contentMode: .aspectFit)
    }
}

/// A Photos asset on the monitor. Unlike the phone's card it holds the last
/// picture until the next is ready, so stepping through never flashes. A small
/// copy goes up first, and the full size is only asked for once the keys pause:
/// PhotoKit can't take a request back, and a held arrow would queue dozens.
private struct MonitorAssetImage: View {
    let asset: PHAsset
    let longEdge: CGFloat
    let fill: Bool

    @State private var image: PlatformImage?

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                Color.clear
            }
        }
        .task(id: "\(asset.localIdentifier)@\(longEdge)") {
            let library = PhotoLibraryService.shared
            if longEdge > 1000 {
                let quick = await library.requestImage(for: asset, targetSize: CGSize(width: 500, height: 500))
                if Task.isCancelled { return }
                image = quick ?? image
                try? await Task.sleep(for: .milliseconds(80))
                if Task.isCancelled { return }
            }
            let full = await library.requestImage(for: asset, targetSize: CGSize(width: longEdge, height: longEdge))
            if !Task.isCancelled { image = full ?? image }
        }
    }
}
