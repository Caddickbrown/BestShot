import Foundation
import Observation

/// Drives the comparison-mode UI: owns a `ComparisonEngine`, resolves the
/// current pair to concrete `MediaItem`s, and exposes progress. Kept separate
/// from the engine so the engine stays pure/testable.
@Observable
@MainActor
final class ComparisonSession: Identifiable {

    let id = UUID()
    let scope: ComparisonScope
    private let itemsByName: [String: MediaItem]
    private var engine: ComparisonEngine

    /// The pair currently shown, or nil when finished.
    private(set) var currentPair: (left: MediaItem, right: MediaItem)?
    private(set) var isFinished = false

    var comparisonsAsked: Int { engine.comparisonsAsked }
    var comparisonsSkipped: Int { engine.comparisonsSkipped }
    var progress: Double { engine.progress }

    init(items: [MediaItem], scope: ComparisonScope) {
        self.scope = scope
        self.itemsByName = Dictionary(items.map { ($0.filename, $0) }, uniquingKeysWith: { a, _ in a })

        let names = items.map(\.filename)
        let ranked = items.filter(\.isRanked).sorted { ($0.rank ?? 0) < ($1.rank ?? 0) }
        let unranked = Set(items.filter { !$0.isRanked }.map(\.filename))

        engine = ComparisonEngine(
            names: names,
            scope: scope,
            rankedOrderNames: ranked.map(\.filename),
            unrankedNames: unranked
        )
        loadNextPair()
    }

    /// The user picked the winning side.
    func choose(winner side: Side) {
        guard let pair = currentPair else { return }
        let (winnerItem, loserItem) = side == .left
            ? (pair.left, pair.right)
            : (pair.right, pair.left)
        engine.recordWin(winner: winnerItem.filename, loser: loserItem.filename)
        engine.advance()
        loadNextPair()
    }

    /// The user marked the pair a tie / skip.
    func skip() {
        engine.skipCurrent()
        loadNextPair()
    }

    private func loadNextPair() {
        if let pair = engine.nextUnknownPair(),
           let left = itemsByName[pair.left],
           let right = itemsByName[pair.right] {
            currentPair = (left, right)
        } else {
            currentPair = nil
            isFinished = true
        }
    }

    /// Final ranking as concrete items, best-first, for the results screen.
    func finalItems() -> [MediaItem] {
        engine.finalRanking().compactMap { itemsByName[$0] }
    }

    func finalOrderNames() -> [String] {
        engine.finalRanking()
    }

    enum Side { case left, right }
}
