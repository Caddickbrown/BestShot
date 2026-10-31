import SwiftUI
import Observation

/// Draws the photos on a rank board. The Photos library and Mac folders each
/// provide one, so the same Rank and Compare screens serve both.
@MainActor
protocol RankMedia: AnyObject {
    func thumbnail(_ id: String) -> AnyView
    func fullImage(_ id: String) -> AnyView
    func caption(_ id: String) -> String
}

/// A set of photos that can be ranked, e.g. "Kept" or "Not rejected".
struct RankPool: Identifiable, Equatable {
    let id: String
    let title: String
    /// Ids in display order.
    let ids: [String]
}

/// Ranking state shared by the Rank sheet and Compare: which photos take part,
/// the saved order (best first), and the running Compare session, if any.
/// The ordering logic itself is the shared Rust core (`RankSession`).
@Observable
@MainActor
final class RankBoard {
    let title: String
    let media: RankMedia
    var pools: [RankPool] {
        didSet { if !pools.contains(where: { $0.id == poolID }) { poolID = pools.first?.id ?? "" } }
    }
    var poolID: String
    /// The full saved ranking, which may include photos outside the current pool.
    private(set) var ranking: [String]
    var compare: CompareRun?

    private let persist: ([String]) -> Void

    init(title: String, media: RankMedia, pools: [RankPool], ranking: [String], persist: @escaping ([String]) -> Void) {
        self.title = title
        self.media = media
        self.pools = pools
        self.poolID = pools.first?.id ?? ""
        self.ranking = ranking
        self.persist = persist
    }

    var pool: [String] { pools.first(where: { $0.id == poolID })?.ids ?? [] }

    /// Pool photos in rank order.
    var ranked: [String] {
        let inPool = Set(pool)
        return ranking.filter(inPool.contains)
    }

    /// Pool photos not ranked yet, in display order.
    var unranked: [String] {
        let placed = Set(ranking)
        return pool.filter { !placed.contains($0) }
    }

    /// Replaces the order of the pool's photos; photos ranked outside the pool
    /// keep their place after them.
    func save(poolOrder: [String]) {
        let inPool = Set(pool).union(poolOrder)
        ranking = poolOrder + ranking.filter { !inPool.contains($0) }
        persist(ranking)
    }

    /// Drag-to-reorder: puts `id` before `target`, or at the end of the ranking.
    func move(_ id: String, before target: String?) {
        guard id != target else { return }
        var order = ranked.filter { $0 != id }
        if let target, let i = order.firstIndex(of: target) {
            order.insert(id, at: i)
        } else {
            order.append(id)
        }
        save(poolOrder: order)
    }

    func clear() {
        save(poolOrder: [])
    }

    func startCompare(scope: RankScope) {
        let ids = ranked + unranked
        guard ids.count >= 2 else { return }
        compare = CompareRun(session: RankSession(ids: ids, ranking: ranking, scope: scope))
    }

    /// Ends Compare, keeping the answers so far when `save` is true.
    func finishCompare(save keep: Bool) {
        if keep, let run = compare, run.progress.asked > 0 {
            save(poolOrder: run.session.order())
        }
        compare = nil
    }
}

/// One Compare session in progress.
@Observable
@MainActor
final class CompareRun: Identifiable {
    let id = UUID()
    let session: RankSession
    private(set) var pair: RankPair?
    private(set) var progress: RankProgress
    /// Bumped on each answer, to flash the chosen side.
    private(set) var lastChoice: RankChoice?

    init(session: RankSession) {
        self.session = session
        self.pair = session.currentPair()
        self.progress = session.progress()
    }

    var isFinished: Bool { pair == nil }

    func choose(_ choice: RankChoice) {
        guard pair != nil else { return }
        session.choose(choice: choice)
        lastChoice = choice
        refresh()
    }

    func undo() {
        if session.undo() {
            lastChoice = nil
            refresh()
        }
    }

    private func refresh() {
        pair = session.currentPair()
        progress = session.progress()
    }
}
