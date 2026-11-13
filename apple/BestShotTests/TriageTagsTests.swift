import XCTest

@testable import BestShot

/// The tags typed at the start of a Triage run.
final class TriageTagsTests: XCTestCase {
    func testSplitsAtCommasAndTrims() {
        XCTAssertEqual(TriageTags.parse(" holiday,Rome , 2026 "), ["holiday", "Rome", "2026"])
    }

    func testEachTagOnceWhateverItsCase() {
        XCTAssertEqual(TriageTags.parse("Rome, rome, ROME, trams"), ["Rome", "trams"])
    }

    func testNothingTypedIsNoTags() {
        XCTAssertEqual(TriageTags.parse(""), [])
        XCTAssertEqual(TriageTags.parse(" , ,"), [])
    }
}
