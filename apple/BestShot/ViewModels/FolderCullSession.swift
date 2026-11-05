#if os(macOS)
import Foundation
import Observation
import SwiftUI

/// Culling a folder of files on the Mac: the same flow, keys and files as the
/// Linux app, backed by the shared Rust core. `FolderCatalog` owns the items,
/// decisions and XMP; this mirrors what the views need.
@Observable
@MainActor
final class FolderCullSession {

    enum Mode: Equatable { case loupe, grid, rank }

    let root: URL
    let name: String
    private let catalog: FolderCatalog
    private(set) var items: [FolderItem] = []
    private(set) var rows: [String: MetaRow] = [:]
    private(set) var counts = FolderCounts(keep: 0, reject: 0, other: 0, left: 0)
    private(set) var keywords: [KeywordCount] = []
    private(set) var problems: [MetaProblem] = []
    /// Item positions that pass the filter, in sort order: what the grid shows
    /// and what next and previous walk through.
    private(set) var visible: [Int] = []
    var index = 0
    var mode: Mode = .loupe
    var filter = FolderFilter.all { didSet { if filter != oldValue { refilter(followFilter: true) } } }
    var sort = FolderSort.name { didSet { if sort != oldValue { refilter(followFilter: true) } } }
    var zoomed = false
    var showInfo = false
    var showKeywords = false
    var showFinish = false
    /// The Finish sheet offers the Trash and nothing else.
    var finishTrashOnly = false
    var showDone = false
    var showProblems = false
    /// The quick-add field has focus, so keys are text rather than commands.
    var typingKeyword = false
    /// Bumped to put the cursor in the quick-add field.
    private(set) var keywordFocusRequest = 0
    /// Grid width in photos, for up and down.
    var gridColumns = 1
    var warning: String?
    /// The photo no longer matches the filter but stays up until you move on.
    private var heldPosition: Int?
    private var undoStack: [(rel: String, previous: MetaSnapshot)] = []

    let recursive: Bool
    let includeVideos: Bool

    /// Ranking for this folder, saved into `.bestshot-cull.json`.
    private(set) var rankBoard: RankBoard?
    private let media = FolderRankMedia()

    private init(root: URL, catalog: FolderCatalog, recursive: Bool, includeVideos: Bool) {
        self.root = root
        self.name = root.lastPathComponent
        self.catalog = catalog
        self.recursive = recursive
        self.includeVideos = includeVideos
    }

    /// Scans `root` off the main actor and loads its saved decisions and XMP.
    static func open(_ root: URL, recursive: Bool, includeVideos: Bool) async throws -> FolderCullSession {
        let path = root.path
        let settings = LabelStore.shared.settings
        let writeJPEG = LabelStore.shared.writeJPEG
        let catalog = try await Task.detached(priority: .userInitiated) {
            try FolderCatalog.open(root: path, recursive: recursive, includeVideos: includeVideos, settings: settings, writeJpeg: writeJPEG)
        }.value
        let session = FolderCullSession(root: root, catalog: catalog, recursive: recursive, includeVideos: includeVideos)
        session.reload()
        session.warning = catalog.takeWarning()
        session.index = session.nextUnreviewed(from: 0) ?? 0
        session.media.root = root
        session.rebuildRankBoard()
        return session
    }

    /// Picks up everything from the catalog.
    private func reload() {
        items = catalog.items()
        rows = Dictionary(uniqueKeysWithValues: catalog.rows().map { ($0.rel, $0) })
        keywords = catalog.keywords()
        problems = catalog.problems()
        counts = catalog.counts()
        visible = catalog.query(filter: filter, sort: sort).map(Int.init)
    }

    /// New label names, a new mapping or the JPEG option: colours are worked
    /// out from text already in memory, so this is quick.
    func settingsChanged() {
        catalog.configure(settings: LabelStore.shared.settings, writeJpeg: LabelStore.shared.writeJPEG)
        reload()
        rebuildRankBoard()
    }

    /// Saves the index. Only a cache, so leaving the folder is soon enough.
    func flush() { catalog.flush() }

    // MARK: - Lookups

    var current: FolderItem? { items.indices.contains(index) ? items[index] : nil }

    func url(for item: FolderItem) -> URL { root.appendingPathComponent(item.rel) }

    func row(at i: Int) -> MetaRow? {
        items.indices.contains(i) ? rows[items[i].rel] : nil
    }

    func decision(at i: Int) -> Decision? { row(at: i)?.decision }

    var rejects: [FolderItem] { items.filter { rows[$0.rel]?.decision == .reject } }

    func companions(of item: FolderItem) -> [String] { catalog.companions(rel: item.rel) }

    /// Nothing passes the filter and no photo is being held up.
    var noMatches: Bool { visible.isEmpty && heldPosition == nil }

    /// Where the current photo sits in `visible`, from 0.
    var position: Int? { visible.firstIndex(of: index) }

    func nextUnreviewed(from start: Int) -> Int? {
        guard !visible.isEmpty else { return nil }
        let first = visible.firstIndex { $0 >= start } ?? 0
        for k in 0..<visible.count {
            let j = visible[(first + k) % visible.count]
            if row(at: j)?.reviewed != true { return j }
        }
        return nil
    }

    // MARK: - Navigation

    func show(_ i: Int) {
        guard !items.isEmpty else { return }
        index = min(max(i, 0), items.count - 1)
        heldPosition = nil
        zoomed = false
        showDone = false
    }

    /// Moves through `visible`. A photo that has just left the filter counts
    /// as sitting where it was.
    private func step(_ delta: Int) {
        guard !visible.isEmpty else { return }
        let target: Int
        if let position {
            target = position + delta
        } else {
            let held = heldPosition ?? 0
            target = delta > 0 ? held + delta - 1 : held + delta
        }
        show(visible[min(max(target, 0), visible.count - 1)])
    }

    func next() { step(1) }
    func previous() { step(-1) }

    func jumpToNextUnreviewed() {
        if let j = nextUnreviewed(from: index + 1) { show(j) }
    }

    // MARK: - Commands

    /// Runs a command from the keyboard, or from anything else that wants the
    /// same behaviour. See `FolderKeymap`.
    func perform(_ command: FolderCommand) {
        switch command {
        case .keep: decide(.keep)
        case .reject: decide(.reject)
        case .next: next()
        case .previous: previous()
        case .first: if let first = visible.first { show(first) }
        case .last: if let last = visible.last { show(last) }
        case .up: step(-max(gridColumns, 1))
        case .down: step(max(gridColumns, 1))
        case .undo: undo()
        case .clearDecision: clearDecision()
        case .nextUnreviewed: jumpToNextUnreviewed()
        case .rate(let stars): rate(stars)
        case .label(let colour): toggleLabel(colour)
        case .toggleZoom: zoomed.toggle()
        case .toggleInfo: showInfo.toggle()
        case .toggleKeywords: toggleKeywords()
        case .toggleGrid: mode = mode == .grid ? .loupe : .grid
        case .toggleRank: mode = mode == .rank ? .loupe : .rank
        case .open: mode = .loupe
        case .trashRed: confirmTrashRed()
        case .escape:
            if zoomed { zoomed = false } else if mode != .loupe { mode = .loupe } else { showDone = false }
        }
    }

    func toggleKeywords() {
        if mode == .grid { mode = .loupe }
        showKeywords.toggle()
        if showKeywords { keywordFocusRequest += 1 }
    }

    func confirmTrashRed() {
        finishTrashOnly = true
        showFinish = true
    }

    func confirmFinish() {
        finishTrashOnly = false
        showFinish = true
    }

    // MARK: - Marks

    /// Runs a write. A failure is shown and changes nothing here, because the
    /// catalog only updates once the file has been written.
    @discardableResult
    private func mark(_ rel: String, _ write: () throws -> MarkResult) -> Bool {
        let previous = catalog.snapshot(rel: rel)
        do {
            let result = try write()
            if catalog.snapshot(rel: rel) != previous {
                undoStack.append((rel, previous))
                if undoStack.count > 1000 { undoStack.removeFirst() }
            }
            applied(result)
            return true
        } catch {
            warning = message(for: error)
            return false
        }
    }

    private func applied(_ result: MarkResult) {
        let old = rows[result.row.rel]
        rows[result.row.rel] = result.row
        if let text = result.warning { warning = text }
        counts = catalog.counts()
        if old?.keywords != result.row.keywords { keywords = catalog.keywords() }
        refilter(followFilter: false)
        if old?.decision != result.row.decision { rebuildRankBoard() }
    }

    private func message(for error: Error) -> String {
        (error as? CoreError)?.message ?? error.localizedDescription
    }

    private func refilter(followFilter: Bool) {
        let previous = position
        visible = catalog.query(filter: filter, sort: sort).map(Int.init)
        guard position == nil else {
            heldPosition = nil
            return
        }
        if followFilter {
            heldPosition = nil
            if let first = visible.first { show(first) }
        } else if let previous {
            heldPosition = previous
        }
    }

    /// Records a decision and moves on, like the Linux app: to the next photo,
    /// wrapping to the first unreviewed one at the end. Keep is green and
    /// reject is red, so this writes the label too.
    func decide(_ decision: Decision) {
        guard let item = current else { return }
        guard mark(item.rel, { try catalog.setDecision(rel: item.rel, decision: decision) }) else { return }
        let atEnd = (position ?? heldPosition ?? 0) >= visible.count - 1
        if counts.left == 0 {
            step(1)
            showDone = true
        } else if !atEnd {
            step(1)
        } else if let j = nextUnreviewed(from: 0) {
            show(j)
        }
    }

    func clearDecision() {
        guard let item = current else { return }
        mark(item.rel) { try catalog.setDecision(rel: item.rel, decision: nil) }
    }

    func rate(_ stars: UInt8) {
        guard let item = current else { return }
        mark(item.rel) { try catalog.setRating(rel: item.rel, stars: stars) }
    }

    /// Sets a colour and stays put, so pressing the key again clears it.
    func toggleLabel(_ colour: LabelColour) {
        guard let item = current else { return }
        mark(item.rel) { try catalog.toggleColour(rel: item.rel, colour: colour) }
    }

    func addKeyword(_ keyword: String) {
        guard let item = current else { return }
        mark(item.rel) { try catalog.addKeyword(rel: item.rel, keyword: keyword) }
    }

    func removeKeyword(_ keyword: String) {
        guard let item = current else { return }
        mark(item.rel) { try catalog.removeKeyword(rel: item.rel, keyword: keyword) }
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        do {
            applied(try catalog.restore(rel: last.rel, snapshot: last.previous))
            if mode == .loupe, let i = items.firstIndex(where: { $0.rel == last.rel }) { show(i) }
        } catch {
            warning = message(for: error)
        }
    }

    // MARK: - Filters

    func toggle(_ pick: LabelPick) {
        if let i = filter.labels.firstIndex(of: pick) {
            filter.labels.remove(at: i)
        } else {
            filter.labels.append(pick)
        }
    }

    func toggleKeywordFilter(_ keyword: String) {
        if let i = filter.keywords.firstIndex(of: keyword) {
            filter.keywords.remove(at: i)
        } else {
            filter.keywords.append(keyword)
        }
    }

    // MARK: - Rank

    private func rebuildRankBoard() {
        let kept = items.filter { rows[$0.rel]?.decision == .keep }.map(\.rel)
        let notRejected = items.filter { rows[$0.rel]?.decision != .reject }.map(\.rel)
        let pools = [
            RankPool(id: "keep", title: "Kept", ids: kept),
            RankPool(id: "all", title: "Not rejected", ids: notRejected),
        ]
        if let rankBoard {
            rankBoard.pools = pools
        } else {
            rankBoard = RankBoard(title: name, media: media, pools: pools, ranking: catalog.ranking()) { [weak self] ranking in
                guard let self else { return }
                do {
                    try self.catalog.setRanking(ranking: ranking)
                } catch {
                    self.warning = "Couldn't save the ranking: \(self.message(for: error))"
                }
            }
        }
    }

    // MARK: - Finish

    /// Moves rejects (and their Live Photo / sidecar companions) to the Trash
    /// or `_Rejected/`. The catalog rescans afterwards.
    func applyCull(mode: CullMode) async -> CullOutcome {
        let catalog = self.catalog
        let outcome = await Task.detached(priority: .userInitiated) {
            catalog.applyCull(mode: mode, trasher: FileManagerTrasher())
        }.value
        reload()
        if let text = catalog.takeWarning() { warning = text }
        undoStack.removeAll()
        heldPosition = nil
        index = nextUnreviewed(from: 0) ?? visible.first ?? 0
        rebuildRankBoard()
        return outcome
    }
}

extension MetaRow {
    /// Has anything been decided about this photo?
    var reviewed: Bool { decision != nil || colour != nil }
}

/// Draws folder files for the rank board.
@MainActor
final class FolderRankMedia: RankMedia {
    var root: URL?

    func thumbnail(_ id: String) -> AnyView {
        guard let root else { return AnyView(Theme.table.tile) }
        return AnyView(FolderImage(url: root.appendingPathComponent(id), maxPixel: 480, contentMode: .fill))
    }

    func fullImage(_ id: String) -> AnyView {
        guard let root else { return AnyView(Color.black) }
        return AnyView(FolderImage(url: root.appendingPathComponent(id), maxPixel: 2400, contentMode: .fit))
    }

    func caption(_ id: String) -> String { (id as NSString).lastPathComponent }
}
#endif
