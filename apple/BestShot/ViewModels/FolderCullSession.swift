#if os(macOS)
import Foundation
import Observation
import SwiftUI

/// Culling a folder of files on the Mac: the same flow, keys and
/// `.bestshot-cull.json` as the Linux app, backed by the shared Rust core.
@Observable
@MainActor
final class FolderCullSession {

    enum Mode: Equatable { case loupe, grid, rank }
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", unreviewed = "Unreviewed", keep = "Kept", reject = "Rejected"
        var id: String { rawValue }
    }

    let root: URL
    let name: String
    private(set) var items: [FolderItem] = []
    private(set) var store: CullStore = .empty
    var index = 0
    var mode: Mode = .loupe
    var filter: Filter = .all
    var zoomed = false
    var showInfo = false
    var showFinish = false
    var showDone = false
    private(set) var warning: String?
    private var undoStack: [(index: Int, previous: Decision?)] = []

    let recursive: Bool
    let includeVideos: Bool

    /// Ranking for this folder, saved into `.bestshot-cull.json`.
    private(set) var rankBoard: RankBoard?
    private let media = FolderRankMedia()

    private init(root: URL, recursive: Bool, includeVideos: Bool) {
        self.root = root
        self.name = root.lastPathComponent
        self.recursive = recursive
        self.includeVideos = includeVideos
    }

    /// Scans `root` off the main actor and loads its saved decisions.
    static func open(_ root: URL, recursive: Bool, includeVideos: Bool) async throws -> FolderCullSession {
        let path = root.path
        let (items, loaded) = try await Task.detached(priority: .userInitiated) {
            (try scanFolder(root: path, recursive: recursive, includeVideos: includeVideos), loadStore(root: path))
        }.value
        let session = FolderCullSession(root: root, recursive: recursive, includeVideos: includeVideos)
        session.items = items
        session.store = loaded.store
        session.warning = loaded.warning
        session.index = session.nextUnreviewed(from: 0) ?? 0
        session.media.root = root
        session.rebuildRankBoard()
        return session
    }

    // MARK: - Lookups

    var current: FolderItem? { items.indices.contains(index) ? items[index] : nil }

    func url(for item: FolderItem) -> URL { root.appendingPathComponent(item.rel) }

    func decision(at i: Int) -> Decision? {
        items.indices.contains(i) ? store.decisions[items[i].rel] : nil
    }

    var counts: (keep: Int, reject: Int, left: Int) {
        var keep = 0, reject = 0
        for item in items {
            switch store.decisions[item.rel] {
            case .keep: keep += 1
            case .reject: reject += 1
            case nil: break
            }
        }
        return (keep, reject, items.count - keep - reject)
    }

    var filteredIndices: [Int] {
        items.indices.filter { i in
            let d = store.decisions[items[i].rel]
            switch filter {
            case .all: return true
            case .unreviewed: return d == nil
            case .keep: return d == .keep
            case .reject: return d == .reject
            }
        }
    }

    var rejects: [FolderItem] { items.filter { store.decisions[$0.rel] == .reject } }

    func nextUnreviewed(from start: Int) -> Int? {
        guard !items.isEmpty else { return nil }
        for k in 0..<items.count {
            let j = (start + k) % items.count
            if store.decisions[items[j].rel] == nil { return j }
        }
        return nil
    }

    // MARK: - Navigation

    func show(_ i: Int) {
        guard !items.isEmpty else { return }
        index = min(max(i, 0), items.count - 1)
        zoomed = false
        showDone = false
    }

    func next() { show(index + 1) }
    func previous() { show(index - 1) }

    func jumpToNextUnreviewed() {
        if let j = nextUnreviewed(from: index + 1) { show(j) }
    }

    // MARK: - Decisions

    /// Records a decision and moves on, like the Linux app: to the next photo,
    /// wrapping to the first unreviewed one at the end.
    func decide(_ decision: Decision) {
        guard let item = current else { return }
        let previous = store.decisions[item.rel]
        if previous != decision {
            set(decision, for: item.rel)
            undoStack.append((index, previous))
            if undoStack.count > 1000 { undoStack.removeFirst() }
        }
        if counts.left == 0 {
            show(min(index + 1, items.count - 1))
            showDone = true
        } else if index < items.count - 1 {
            show(index + 1)
        } else if let j = nextUnreviewed(from: 0) {
            show(j)
        }
    }

    func clearDecision() {
        guard let item = current, let previous = store.decisions[item.rel] else { return }
        set(nil, for: item.rel)
        undoStack.append((index, previous))
    }

    func undo() {
        guard let last = undoStack.popLast(), items.indices.contains(last.index) else { return }
        set(last.previous, for: items[last.index].rel)
        if mode == .loupe { show(last.index) }
    }

    private func set(_ decision: Decision?, for rel: String) {
        store.decisions[rel] = decision
        persist()
        rebuildRankBoard()
    }

    private func persist() {
        do {
            try saveStore(root: root.path, store: store)
        } catch let error as CoreError {
            warning = "Couldn't save decisions: \(error.message)"
        } catch {
            warning = "Couldn't save decisions: \(error.localizedDescription)"
        }
    }

    // MARK: - Rank

    private func rebuildRankBoard() {
        let kept = items.filter { store.decisions[$0.rel] == .keep }.map(\.rel)
        let notRejected = items.filter { store.decisions[$0.rel] != .reject }.map(\.rel)
        let pools = [
            RankPool(id: "keep", title: "Kept", ids: kept),
            RankPool(id: "all", title: "Not rejected", ids: notRejected),
        ]
        if let rankBoard {
            rankBoard.pools = pools
        } else {
            rankBoard = RankBoard(title: name, media: media, pools: pools, ranking: store.ranking) { [weak self] ranking in
                guard let self else { return }
                self.store.ranking = ranking
                self.persist()
            }
        }
    }

    // MARK: - Finish

    /// Moves rejects (and their Live Photo / sidecar companions) to the Trash
    /// or `_Rejected/`, then rescans.
    func applyCull(mode: CullMode) async -> CullOutcome {
        let path = root.path
        let rejects = self.rejects
        let outcome = await Task.detached(priority: .userInitiated) {
            BestShot.applyCull(root: path, rejects: rejects, mode: mode, trasher: FileManagerTrasher())
        }.value
        for rel in outcome.culled {
            store.decisions[rel] = nil
        }
        store.ranking.removeAll { outcome.culled.contains($0) }
        persist()
        if let refreshed = try? scanFolder(root: path, recursive: recursive, includeVideos: includeVideos) {
            items = refreshed
        }
        undoStack.removeAll()
        index = nextUnreviewed(from: 0) ?? 0
        rebuildRankBoard()
        return outcome
    }
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
