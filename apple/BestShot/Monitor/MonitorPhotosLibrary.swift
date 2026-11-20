import SwiftUI
import SwiftData
import Photos

/// The monitor's way to the real thing: the Triage and Organise sessions and the
/// Rank board the phone is on, and the same services and saved records the
/// phone's screens use. The monitor adds
/// no way of its own to delete: `commitDeletions` is the session's.
@Observable
@MainActor
final class MonitorPhotosLibrary: MonitorLibrary {
    private let context: ModelContext
    private let triage: TriageHolder
    private let organiseHolder: OrganiseHolder
    private let rank: RankHolder
    private let photos = PhotoLibraryService.shared
    private let labels = LabelStore.shared
    private var access = PhotoLibraryService.shared.status
    private var albums: [PHAssetCollection] = []
    /// Photos in each album, by id, counted off the main thread. An album
    /// isn't offered until it's counted, and never when it's empty.
    private var albumCounts: [String: Int] = [:]
    @ObservationIgnored private var counting: Task<Void, Never>?
    /// Filled in as photos are looked up, which a redraw mustn't trigger.
    @ObservationIgnored private var assets: [String: PHAsset] = [:]
    @ObservationIgnored private var idCache: (session: ObjectIdentifier, ids: [String])?
    private var organise: OrganiseSession? { organiseHolder.session }

    /// The holders default to the app's shared ones. They're looked up in the
    /// body, on the main actor: a default argument (`= .shared`) is evaluated
    /// by the caller outside the actor, which Swift 6 rejects.
    init(context: ModelContext, triage: TriageHolder? = nil, organise: OrganiseHolder? = nil,
         rank: RankHolder? = nil) {
        self.context = context
        self.triage = triage ?? .shared
        self.organiseHolder = organise ?? .shared
        self.rank = rank ?? .shared
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
    var triageShowing: Bool { triage.session != nil && !triage.paused }

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
            + AlbumList.sources(albums, query: "", title: \.localizedTitle, count: { self.albumCounts[$0.localIdentifier] })
                .map { (.album($0.localIdentifier), $0.localizedTitle ?? "Album") }
    }

    func reloadSources() {
        access = photos.status
        guard hasPhotoAccess else { return }
        albums = photos.userAlbums()
        let all = albums
        counting?.cancel()
        counting = Task { [weak self] in
            let counts = await Task.detached { PhotoLibraryService.shared.photoCounts(all) }.value
            guard !Task.isCancelled else { return }
            self?.albumCounts = counts
        }
    }

    func startTriage(order: SessionOrder, source: TriageSourceOption, tags: [String]) async -> String? {
        guard triage.session == nil else { return nil }
        guard await HiddenGate.shared.allows(source) else { return "Hidden stays locked without Face ID." }
        let found = TriageHomeView.fetchSession(order: order, source: source, context: context)
        guard !found.isEmpty else {
            return source.nothingFound("No unreviewed photos found for this source. Try another source or order.")
        }
        assets = Dictionary(found.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        triage.paused = false
        triage.session = TriageSession(assets: found, context: context, tags: tags, marks: tags.isEmpty ? nil : .shared)
        return nil
    }

    // Photos marked to delete by a run that ended early: the phone's start screen's
    // "Delete Them" and "Keep Them", lifted out of the view.

    private var waitingReviews: [AssetReview] {
        ((try? context.fetch(FetchDescriptor<AssetReview>())) ?? []).filter { $0.decision == .deleted }
    }

    var waitingDeletes: Int {
        guard triage.session == nil else { return 0 }
        let ids = waitingReviews.map(\.assetLocalID)
        guard !ids.isEmpty else { return 0 }
        return PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count
    }

    func deleteWaiting() async -> Int {
        let ids = waitingReviews.map(\.assetLocalID)
        let found = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        let assets = found.objects(at: IndexSet(0..<found.count))
        guard !assets.isEmpty else { return 0 }
        return await photos.deleteAssets(assets) ? assets.count : 0
    }

    func keepWaiting() {
        for review in waitingReviews { context.delete(review) }
        try? context.save()
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
        return rank.board(context: context)
    }

    func saveRankAlbum(_ ids: [String]) async -> String {
        await PhotosRankView.saveAlbum(ids.compactMap { rank.media.assets[$0] })
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
        guard !found.isEmpty else { return source.nothingFound("No unorganised photos found for this source.") }
        for asset in found { assets[asset.localIdentifier] = asset }
        let albums = photos.userAlbumsWithFolders()
        organiseHolder.start(OrganiseSession(assets: found, albums: albums.albums, folders: albums.folders, context: context))
        return nil
    }

    func startOrganise(folder: URL, order: SessionOrder) async -> String? {
        switch await OrganiseSession.fromFolder(folder, order: order, context: context) {
        case .success(let started):
            organiseHolder.start(started)
            return nil
        case .failure(let problem):
            return problem.message
        }
    }

    /// Photo files from Files, by their item id, for their pictures. The session
    /// may have been started on the phone, so they're found in it as they're asked for.
    @ObservationIgnored private var files: [String: URL] = [:]

    private func file(_ id: String) -> URL? {
        if let known = files[id] { return known }
        guard id.hasPrefix("file:"), let organise else { return nil }
        for case .file(let url) in organise.items where OrganiseItem.file(url).id == id {
            files[id] = url
            return url
        }
        return nil
    }

    func addToAlbum(_ id: String) async {
        guard let organise, let item = organise.currentItem,
              let album = organise.albums.first(where: { $0.localIdentifier == id }) else { return }
        await organise.pick(item, album: album)
    }

    func newAlbum(_ title: String) async {
        guard let organise, let item = organise.currentItem else { return }
        await organise.createAlbumAndAdd(name: title, item: item)
    }

    var organiseCanUndo: Bool { organise?.canUndo ?? false }

    func undoOrganise() async -> String? {
        guard let organise else { return nil }
        return await organise.undo()
    }

    func nextOrganised() { organise?.next() }
    func skipOrganised() { organise?.skip() }

    var organiseOpen: Bool { organiseHolder.isOpen }

    var organiseOneAlbum: Bool {
        get { organise?.singleAlbum ?? UserDefaults.standard.bool(forKey: "organise.singleAlbum") }
        set {
            if let organise { organise.singleAlbum = newValue } else { UserDefaults.standard.set(newValue, forKey: "organise.singleAlbum") }
        }
    }
    func resumeOrganise() { organiseHolder.resume() }

    /// Anything filed is filed already, and each step saves as it goes. The place
    /// and Undo wait to be resumed, here or on the phone.
    func leaveOrganise() { organiseHolder.leave() }

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
                             detail: ([$0.project?.name, $0.rank.map { "#\($0 + 1)" }, $0.tags.isEmpty ? nil : $0.tags.joined(separator: ", ")])
                                .compactMap { $0 }.joined(separator: " · "),
                             tags: $0.tags, note: $0.comment, isVideo: $0.mediaType == .video, rank: $0.rank,
                             size: $0.fileSize, imported: $0.importedAt, project: $0.project?.name)
        }
    }

    @ObservationIgnored private var fullSize: [String: URL] = [:]

    private func project(_ id: UUID) -> Project? {
        (try? context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.uuid == id })))?.first
    }

    private func item(_ id: String) -> MediaItem? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return (try? context.fetch(FetchDescriptor<MediaItem>(predicate: #Predicate { $0.uuid == uuid })))?.first
    }

    func newProject(_ name: String) -> UUID? {
        guard let clean = ProjectLibrary.cleanName(name) else { return nil }
        let all = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let project = Project(name: clean, sortIndex: (all.map(\.sortIndex).max() ?? 0) + 1)
        context.insert(project)
        try? context.save()
        return project.uuid
    }

    func renameProject(_ id: UUID, to name: String) -> Bool {
        guard let project = project(id) else { return false }
        return ProjectLibrary.rename(project, to: name, context: context)
    }

    func projectRemoval(_ id: UUID) -> String {
        project(id).map(ProjectLibrary.removalMessage) ?? ""
    }

    func removeProject(_ id: UUID) async -> String? {
        // The phone lets go of the project first, if it's showing it.
        AppCommands.shared.send(.projectRemoved(id))
        try? await Task.sleep(for: .milliseconds(300))
        guard let project = project(id) else { return nil }
        do {
            try ProjectLibrary.remove(project, context: context)
            return nil
        } catch {
            return "Its photos couldn't be moved to Files, so it's been kept. \(error.localizedDescription)"
        }
    }

    func setMediaTags(_ id: String, _ tags: [String]) {
        guard let item = item(id) else { return }
        var seen = Set<String>()
        item.tags = tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        try? context.save()
    }

    func setMediaNote(_ id: String, _ note: String) {
        guard let item = item(id) else { return }
        item.comment = note
        try? context.save()
    }

    func projectBoard(_ id: UUID) -> RankBoard? {
        guard let project = project(id) else { return nil }
        let items = project.items
        let ids = items.sorted(by: SortOption.rank.comparator).map(\.uuid.uuidString)
        let ranking = items.filter { $0.rank != nil }.sorted(by: SortOption.rank.comparator).map(\.uuid.uuidString)
        let context = context
        return RankBoard(title: project.name, media: ProjectRankMedia(library: self),
                         pools: [RankPool(id: "project", title: project.name, ids: ids)], ranking: ranking,
                         persist: { [weak self] order in
                             guard let self, let project = self.project(id) else { return }
                             let byID = Dictionary(project.items.map { ($0.uuid.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
                             let placed = Set(order)
                             for item in project.items where !placed.contains(item.uuid.uuidString) { item.rank = nil }
                             RankingService.applyOrder(order.compactMap { byID[$0] }, context: context)
                         })
    }

    func clearProjectRankings(_ id: UUID) {
        guard let project = project(id) else { return }
        RankingService.clearRankings(project: project, context: context)
    }

    func caption(_ id: String) -> String { item(id)?.filename ?? "" }

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
        if let url = file(id) ?? (longEdge > 500 ? fullSize[id] : items[id]) {
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
                let quick = await library.requestImage(for: asset, targetSize: CGSize(width: 500, height: 500))?.platform
                if Task.isCancelled { return }
                image = quick ?? image
                try? await Task.sleep(for: .milliseconds(80))
                if Task.isCancelled { return }
            }
            let full = await library.requestImage(for: asset, targetSize: CGSize(width: longEdge, height: longEdge))?.platform
            if !Task.isCancelled { image = full ?? image }
        }
    }
}

/// A project's photos, drawn for the monitor's Compare.
@MainActor
private final class ProjectRankMedia: RankMedia {
    weak var library: MonitorPhotosLibrary?
    init(library: MonitorPhotosLibrary) { self.library = library }
    func thumbnail(_ id: String) -> AnyView { library?.picture(id, longEdge: 400, fill: true) ?? AnyView(Color.clear) }
    func fullImage(_ id: String) -> AnyView { library?.picture(id, longEdge: 2600, fill: false) ?? AnyView(Color.clear) }
    func caption(_ id: String) -> String { library?.caption(id) ?? "" }
}
