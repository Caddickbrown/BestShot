import Foundation

/// A Compare session over string ids: Photos `localIdentifier`s or
/// folder-relative paths. Wraps `ComparisonEngine` (the transitive-inference
/// port) and adds undo plus the ordering rules shared with the Linux app
/// (`desktop/src/rank.js` `RankEngine.order`).
///
/// Pure value type, independent of UI, so it can be unit-tested.
struct RankSession {

    enum Choice { case left, right, skip }

    /// Everything taking part, in display order.
    let ids: [String]
    /// The order that existed before this session (best first), limited to `ids`.
    let prior: [String]
    let scope: ComparisonScope

    private(set) var engine: ComparisonEngine
    private var history: [ComparisonEngine] = []
    private static let historyLimit = 30

    /// - Parameters:
    ///   - ids: every item taking part.
    ///   - ranking: the saved ranking (best first); entries not in `ids` are ignored.
    ///   - scope: `.all` asks about everything; `.unranked` keeps the saved
    ///     order as known results and only asks about unranked items.
    init(
        ids: [String],
        ranking: [String],
        scope: ComparisonScope,
        shuffle: ([ComparisonEngine.Pair]) -> [ComparisonEngine.Pair] = ComparisonEngine.fisherYates
    ) {
        self.ids = ids
        self.scope = scope
        let pool = Set(ids)
        let prior = ranking.filter { pool.contains($0) }
        self.prior = prior
        let priorSet = Set(prior)
        engine = ComparisonEngine(
            names: ids,
            scope: scope,
            rankedOrderNames: prior,
            unrankedNames: Set(ids.filter { !priorSet.contains($0) }),
            shuffle: shuffle
        )
    }

    // MARK: - Progress

    /// The pair to show next, or nil when every relationship is known.
    mutating func currentPair() -> ComparisonEngine.Pair? {
        engine.nextUnknownPair()
    }

    var isFinished: Bool {
        var copy = engine
        return copy.nextUnknownPair() == nil
    }

    var comparisonsAsked: Int { engine.comparisonsAsked }
    var inferred: Int { engine.comparisonsSkipped }
    var totalPairs: Int { engine.allPairs.count }
    var progress: Double { engine.progress }
    var canUndo: Bool { !history.isEmpty }

    // MARK: - Answers

    mutating func choose(_ choice: Choice) {
        guard let pair = engine.nextUnknownPair() else { return }
        history.append(engine)
        if history.count > Self.historyLimit { history.removeFirst() }
        switch choice {
        case .left:
            engine.recordWin(winner: pair.left, loser: pair.right)
            engine.advance()
        case .right:
            engine.recordWin(winner: pair.right, loser: pair.left)
            engine.advance()
        case .skip:
            engine.skipCurrent()
        }
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard let previous = history.popLast() else { return false }
        engine = previous
        return true
    }

    // MARK: - Result

    /// Best first. Items with no known result at all stay unranked, unless
    /// they were ranked before this session. Ties fall back to the previous
    /// rank, then to display order.
    func order() -> [String] {
        let priorRank = Dictionary(uniqueKeysWithValues: prior.enumerated().map { ($1, $0) })
        let position = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        let involved = ids.filter { id in
            priorRank[id] != nil
                || !(engine.beats[id]?.isEmpty ?? true)
                || !(engine.losesTo[id]?.isEmpty ?? true)
        }
        return involved.sorted { a, b in
            let sa = engine.scores[a] ?? 0, sb = engine.scores[b] ?? 0
            if sa != sb { return sa > sb }
            let pa = priorRank[a] ?? .max, pb = priorRank[b] ?? .max
            if pa != pb { return pa < pb }
            return (position[a] ?? 0) < (position[b] ?? 0)
        }
    }

    /// Merges this session's order into a full saved ranking: the session's
    /// items first, then anything previously ranked that wasn't in the pool.
    func mergedRanking(into saved: [String]) -> [String] {
        let ordered = order()
        let placed = Set(ordered)
        return ordered + saved.filter { !placed.contains($0) }
    }
}
