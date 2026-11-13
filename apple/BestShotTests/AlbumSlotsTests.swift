import XCTest
@testable import BestShot

/// Organise's six albums keep their places: a new one takes the place of the
/// one used longest ago, and nothing else moves (Dan, 13 Nov).
final class AlbumSlotsTests: XCTestCase {
    func testUsingAnAlbumAlreadyInTheGridMovesNothing() {
        let slots = ["a", "b", "c", "d", "e", "f"]
        XCTAssertEqual(AlbumRecency.place("c", in: slots, lastUsed: [:], size: 6), slots)
    }

    func testANewAlbumFillsAnEmptyPlaceAtTheEnd() {
        XCTAssertEqual(AlbumRecency.place("x", in: ["a", "b"], lastUsed: [:], size: 6), ["a", "b", "x"])
    }

    func testANewAlbumTakesTheLeastRecentlyUsedPlaceOnly() {
        let slots = ["a", "b", "c", "d", "e", "f"]
        let used: [String: Double] = ["a": 6, "b": 5, "c": 1, "d": 4, "e": 3, "f": 2]
        XCTAssertEqual(AlbumRecency.place("x", in: slots, lastUsed: used, size: 6),
                       ["a", "b", "x", "d", "e", "f"])
    }

    func testAnAlbumWithNoRecordedUseIsTheFirstToGo() {
        let slots = ["a", "b", "c"]
        XCTAssertEqual(AlbumRecency.place("x", in: slots, lastUsed: ["a": 3, "c": 2], size: 3), ["a", "x", "c"])
    }
}
