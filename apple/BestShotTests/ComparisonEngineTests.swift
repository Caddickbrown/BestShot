import XCTest
@testable import BestShot

/// Verifies the Swift `ComparisonEngine` reproduces the web app's
/// transitive-inference ranking behaviour. This is the one component fully
/// testable without a GUI, so it's the anchor for confidence in the port.
final class ComparisonEngineTests: XCTestCase {

    /// Identity shuffle keeps pair order deterministic for assertions.
    private func engine(_ names: [String], scope: ComparisonScope = .all,
                        ranked: [String] = [], unranked: Set<String> = []) -> ComparisonEngine {
        ComparisonEngine(names: names, scope: scope, rankedOrderNames: ranked,
                         unrankedNames: unranked, shuffle: { $0 })
    }

    func testDirectWinRecorded() {
        var e = engine(["A", "B"])
        e.recordWin(winner: "A", loser: "B")
        XCTAssertTrue(e.isRelationshipKnown("A", "B"))
        XCTAssertEqual(e.scores["A"], 1)
        XCTAssertEqual(e.scores["B"], 0)
    }

    /// A beats B, B beats C ⇒ engine infers A beats C without being asked.
    func testTransitiveInference() {
        var e = engine(["A", "B", "C"])
        e.recordWin(winner: "A", loser: "B")
        e.recordWin(winner: "B", loser: "C")
        XCTAssertTrue(e.isRelationshipKnown("A", "C"), "A>C should be inferred transitively")
        XCTAssertTrue(e.beats["A"]?.contains("C") ?? false)
        // A beats B and C ⇒ score 2; B beats C ⇒ 1; C ⇒ 0.
        XCTAssertEqual(e.scores["A"], 2)
        XCTAssertEqual(e.scores["B"], 1)
        XCTAssertEqual(e.scores["C"], 0)
    }

    /// Recording all decisive results yields a total order by score.
    func testFinalRankingByScore() {
        var e = engine(["A", "B", "C"])
        e.recordWin(winner: "A", loser: "B")
        e.recordWin(winner: "B", loser: "C")
        XCTAssertEqual(e.finalRanking(), ["A", "B", "C"])
    }

    /// The session never surfaces a pair whose order is already known.
    func testInferredPairsAreSkipped() {
        // Pairs (identity order): (A,B), (A,C), (B,C)
        var e = engine(["A", "B", "C"])

        let first = e.nextUnknownPair()
        XCTAssertEqual(first?.left, "A"); XCTAssertEqual(first?.right, "B")
        e.recordWin(winner: "A", loser: "B"); e.advance()

        let second = e.nextUnknownPair()
        XCTAssertEqual(second?.left, "A"); XCTAssertEqual(second?.right, "C")
        e.recordWin(winner: "C", loser: "A"); e.advance()
        // Now C>A>B ⇒ C>B is known, so (B,C) must be skipped.
        XCTAssertNil(e.nextUnknownPair(), "Remaining pair (B,C) should be inferred, not asked")
        XCTAssertEqual(e.finalRanking(), ["C", "A", "B"])
    }

    /// Skip/tie adds no edge and simply advances.
    func testSkipAddsNoEdge() {
        var e = engine(["A", "B"])
        _ = e.nextUnknownPair()
        e.skipCurrent()
        XCTAssertFalse(e.isRelationshipKnown("A", "B"))
        XCTAssertNil(e.nextUnknownPair())
    }

    /// Unranked scope seeds the existing order and only asks pairs involving a
    /// new item.
    func testUnrankedScopeSeedsAndFiltersPairs() {
        // Existing ranked order A > B; new item X to place.
        let e = engine(["A", "B", "X"], scope: .unranked,
                       ranked: ["A", "B"], unranked: ["X"])
        // Seeded: A beats B already.
        XCTAssertTrue(e.isRelationshipKnown("A", "B"))
        XCTAssertEqual(e.scores["A"], 1)
        // Every generated pair must involve X.
        for pair in e.allPairs {
            XCTAssertTrue(pair.left == "X" || pair.right == "X",
                          "Unranked scope should only generate pairs including the new item")
        }
    }

    /// Placing a new item at the top via wins pushes it to rank #1.
    func testUnrankedItemRisesToTop() {
        var e = engine(["A", "B", "X"], scope: .unranked,
                       ranked: ["A", "B"], unranked: ["X"])
        // X beats A (and transitively B).
        e.recordWin(winner: "X", loser: "A")
        XCTAssertEqual(e.finalRanking().first, "X")
    }

    func testGeneratePairsCount() {
        // n items ⇒ n*(n-1)/2 pairs.
        XCTAssertEqual(ComparisonEngine.generatePairs(names: ["A", "B", "C", "D"]).count, 6)
    }
}
