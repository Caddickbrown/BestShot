import Foundation

/// Pure-Swift port of the web app's comparison ranking algorithm
/// (`static/app.js` `recordWin` / `isRelationshipKnown` / pair generation).
///
/// The engine maintains a partial order over item names as a set of "beats"
/// edges. Each recorded win is transitively closed so that if A beats B and B
/// beats C, the engine already knows A beats C and never asks that pair. The
/// final ranking is items sorted by score (number of items they beat), which
/// reproduces the web app's `Apply Ranking` behaviour.
///
/// This type is intentionally free of UI/SwiftData dependencies so it can be
/// unit-tested in isolation (see `ComparisonEngineTests`).
struct ComparisonEngine {

    /// A pair still awaiting a decision, referenced by item name.
    typealias Pair = (left: String, right: String)

    // Adjacency: `beats[x]` = set of names x is known to beat (directly or transitively).
    private(set) var beats: [String: Set<String>] = [:]
    private(set) var losesTo: [String: Set<String>] = [:]
    private(set) var scores: [String: Int] = [:]

    /// Candidate pairs to walk through, in presentation order.
    private(set) var allPairs: [Pair] = []
    private(set) var currentPairIndex: Int = 0

    /// Number of pairs actually shown to the user.
    private(set) var comparisonsAsked: Int = 0
    /// Number of pairs resolved by transitive inference (never shown).
    private(set) var comparisonsSkipped: Int = 0

    // MARK: - Construction

    /// Build an engine for a comparison session.
    ///
    /// - Parameters:
    ///   - names: every item name participating in the session.
    ///   - scope: `.all` compares everything from scratch; `.unranked` seeds the
    ///     partial order from the existing ranked order and only surfaces pairs
    ///     that involve at least one unranked item.
    ///   - rankedOrderNames: names of already-ranked items, best-first. Used only
    ///     when `scope == .unranked` to seed the known relationships.
    ///   - unrankedNames: names considered "New" (only used for `.unranked`).
    ///   - shuffle: pair-shuffling hook (Fisher–Yates in production; identity in tests).
    init(
        names: [String],
        scope: ComparisonScope,
        rankedOrderNames: [String] = [],
        unrankedNames: Set<String> = [],
        shuffle: ([Pair]) -> [Pair] = ComparisonEngine.fisherYates
    ) {
        for name in names {
            beats[name] = []
            losesTo[name] = []
            scores[name] = 0
        }

        if scope == .unranked {
            // Seed the known order: earlier (better) beats every later item.
            for i in 0..<rankedOrderNames.count {
                for j in (i + 1)..<rankedOrderNames.count {
                    let winner = rankedOrderNames[i]
                    let loser = rankedOrderNames[j]
                    beats[winner, default: []].insert(loser)
                    losesTo[loser, default: []].insert(winner)
                    scores[winner, default: 0] += 1
                }
            }
            allPairs = shuffle(Self.generatePairsWithUnranked(names: names, unrankedNames: unrankedNames))
        } else {
            allPairs = shuffle(Self.generatePairs(names: names))
        }
    }

    // MARK: - Pair generation

    /// All unordered pairs, shuffled by the caller. Mirrors `generatePairs`.
    static func generatePairs(names: [String]) -> [Pair] {
        var pairs: [Pair] = []
        for i in 0..<names.count {
            for j in (i + 1)..<names.count {
                pairs.append((names[i], names[j]))
            }
        }
        return pairs
    }

    /// Only pairs where at least one member is unranked. Mirrors
    /// `generatePairsWithUnranked`.
    static func generatePairsWithUnranked(names: [String], unrankedNames: Set<String>) -> [Pair] {
        var pairs: [Pair] = []
        for i in 0..<names.count {
            for j in (i + 1)..<names.count {
                if unrankedNames.contains(names[i]) || unrankedNames.contains(names[j]) {
                    pairs.append((names[i], names[j]))
                }
            }
        }
        return pairs
    }

    static func fisherYates(_ pairs: [Pair]) -> [Pair] {
        var result = pairs
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            let j = Int.random(in: 0...i)
            result.swapAt(i, j)
        }
        return result
    }

    // MARK: - Queries

    /// True if we already know the relative order of the two items.
    /// Mirrors `isRelationshipKnown`.
    func isRelationshipKnown(_ a: String, _ b: String) -> Bool {
        (beats[a]?.contains(b) ?? false) || (beats[b]?.contains(a) ?? false)
    }

    /// Advance to and return the next pair whose relationship is still unknown,
    /// or nil when the session is complete. Mirrors `findNextUnknownPair`.
    mutating func nextUnknownPair() -> Pair? {
        var i = currentPairIndex
        while i < allPairs.count {
            let pair = allPairs[i]
            if !isRelationshipKnown(pair.left, pair.right) {
                currentPairIndex = i
                return pair
            }
            i += 1
        }
        currentPairIndex = allPairs.count
        return nil
    }

    // MARK: - Mutation

    /// Record that `winner` is preferred over `loser`, then transitively close
    /// the partial order. Faithful port of `recordWin` (app.js:2567-2602).
    mutating func recordWin(winner: String, loser: String) {
        guard beats[winner]?.contains(loser) == false else { return }

        comparisonsAsked += 1

        beats[winner, default: []].insert(loser)
        losesTo[loser, default: []].insert(winner)
        scores[winner, default: 0] += 1

        // Winner inherits everyone the loser beats.
        for item in beats[loser] ?? [] {
            if beats[winner]?.contains(item) == false {
                beats[winner, default: []].insert(item)
                losesTo[item, default: []].insert(winner)
                scores[winner, default: 0] += 1
                comparisonsSkipped += 1
            }
        }

        // Everyone who beats the winner now also beats the loser and the loser's beats.
        for item in losesTo[winner] ?? [] {
            if beats[item]?.contains(loser) == false {
                beats[item, default: []].insert(loser)
                losesTo[loser, default: []].insert(item)
                scores[item, default: 0] += 1
                comparisonsSkipped += 1
            }
            for subItem in beats[loser] ?? [] {
                if beats[item]?.contains(subItem) == false {
                    beats[item, default: []].insert(subItem)
                    losesTo[subItem, default: []].insert(item)
                    scores[item, default: 0] += 1
                    comparisonsSkipped += 1
                }
            }
        }
    }

    /// Record a tie / skip. The web app treats a skip as "no information", so we
    /// simply move past this pair without adding an edge.
    mutating func skipCurrent() {
        comparisonsAsked += 1
        currentPairIndex += 1
    }

    /// Move the cursor forward after a decided pair so we don't re-show it.
    mutating func advance() {
        currentPairIndex += 1
    }

    // MARK: - Result

    /// Final ranking, best-first, sorted by score descending. Ties broken by
    /// name for determinism.
    func finalRanking() -> [String] {
        scores.keys.sorted { lhs, rhs in
            let ls = scores[lhs] ?? 0
            let rs = scores[rhs] ?? 0
            if ls != rs { return ls > rs }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    /// Fraction of the session resolved (asked + skipped-by-inference) over the
    /// total candidate pairs, for a progress indicator.
    var progress: Double {
        guard !allPairs.isEmpty else { return 1 }
        let resolved = allPairs.enumerated().filter { idx, pair in
            idx < currentPairIndex || isRelationshipKnown(pair.left, pair.right)
        }.count
        return Double(resolved) / Double(allPairs.count)
    }
}
