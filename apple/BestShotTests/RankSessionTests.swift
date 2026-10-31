import XCTest
@testable import BestShot

/// RankSession must order photos the same way the Linux app's rank.js does.
final class RankSessionTests: XCTestCase {

    private func session(_ ids: [String], ranking: [String] = [], scope: ComparisonScope = .all) -> RankSession {
        RankSession(ids: ids, ranking: ranking, scope: scope, shuffle: { $0 })
    }

    /// Answer every question truthfully against `truth` (best first).
    private func answerAll(_ s: inout RankSession, truth: [String]) -> Int {
        var asked = 0
        while let pair = s.currentPair() {
            let leftBetter = truth.firstIndex(of: pair.left)! < truth.firstIndex(of: pair.right)!
            s.choose(leftBetter ? .left : .right)
            asked += 1
        }
        return asked
    }

    func testFullRankingMatchesTruthWithFewerQuestionsThanPairs() {
        let truth = ["a", "b", "c", "d", "e", "f", "g", "h"]
        var s = session(truth.reversed())
        let asked = answerAll(&s, truth: truth)
        XCTAssertEqual(s.order(), truth)
        XCTAssertTrue(s.isFinished)
        XCTAssertLessThan(asked, s.totalPairs)
        XCTAssertGreaterThan(s.inferred, 0)
    }

    func testUnrankedScopeSlotsNewItemsIntoExistingOrder() {
        var s = session(["a", "c", "e", "b", "d"], ranking: ["a", "c", "e"], scope: .unranked)
        _ = answerAll(&s, truth: ["a", "b", "c", "d", "e"])
        XCTAssertEqual(s.order(), ["a", "b", "c", "d", "e"])
    }

    func testUndoRestoresThePreviousQuestion() {
        var s = session(["x", "y"])
        let first = s.currentPair()!
        s.choose(.right)
        XCTAssertTrue(s.isFinished)
        XCTAssertEqual(s.order(), ["y", "x"])
        XCTAssertTrue(s.undo())
        XCTAssertEqual(s.currentPair()?.left, first.left)
        XCTAssertEqual(s.order(), [])
        XCTAssertFalse(s.undo())
    }

    func testPartialOrderOnlyRanksItemsThatWereCompared() {
        var s = session(["p", "q", "r"])
        s.choose(.left) // p beats q
        XCTAssertEqual(s.order(), ["p", "q"])
    }

    func testSkipRecordsNoResult() {
        var s = session(["p", "q"])
        s.choose(.skip)
        XCTAssertTrue(s.isFinished)
        XCTAssertEqual(s.order(), [])
    }

    func testMergedRankingKeepsItemsOutsideThePool() {
        var s = session(["a", "b"], ranking: ["z", "b", "a"])
        s.choose(.left) // a beats b
        XCTAssertEqual(s.mergedRanking(into: ["z", "b", "a"]), ["a", "b", "z"])
    }
}
