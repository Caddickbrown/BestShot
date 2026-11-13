import XCTest
@testable import BestShot

/// The start screen's sources fold into one row once one is chosen (Dan, 13 Nov).
final class SourceFoldTests: XCTestCase {
    func testOpenWhenNothingIsChosenYet() {
        XCTAssertTrue(SourceFold(source: .allPhotos).open)
    }

    func testFoldedWhenComingBackWithASourceChosen() {
        XCTAssertFalse(SourceFold(source: .screenshots).open)
        XCTAssertFalse(SourceFold(source: .album("a")).open)
    }

    func testChoosingFoldsTappingTheRowOpensAndChoosingAgainFolds() {
        var fold = SourceFold(source: .allPhotos)
        fold.choose()
        XCTAssertFalse(fold.open, "a source chosen: one row")
        fold.reopen()
        XCTAssertTrue(fold.open, "the row tapped: every source again")
        fold.choose()
        XCTAssertFalse(fold.open, "another chosen: folded again")
    }
}
