import XCTest

@testable import BestShot

/// Stars and colour labels on a Photos photo in Triage, as the phone and the
/// iPad set them: the same rules the monitor and Folders use.
final class TriageLabelTests: XCTestCase {
    func testAColourSetsItsDecision() {
        var mark = PhotoMark()
        XCTAssertEqual(mark.toggle(.green, shown: nil), .kept)
        XCTAssertEqual(mark.colour, .green)
        XCTAssertEqual(mark.toggle(.red, shown: .green), .deleted)
        XCTAssertEqual(mark.colour, .red)
        XCTAssertEqual(mark.toggle(.yellow, shown: .red), .skipped)
        XCTAssertEqual(mark.toggle(.blue, shown: .yellow), .undecided)
        XCTAssertEqual(mark.toggle(.purple, shown: .blue), .undecided)
    }

    func testTheSameColourAgainClearsIt() {
        var mark = PhotoMark(rating: 3, colourSlug: "green", tags: ["Rome"])
        XCTAssertEqual(mark.toggle(.green, shown: .green), .undecided)
        XCTAssertNil(mark.colour)
        XCTAssertEqual(mark.rating, 3, "a colour never touches the stars")
        XCTAssertEqual(mark.tags, ["Rome"])
    }

    /// A kept photo shows green with no colour of its own, so pressing green clears the keep.
    func testTheShownColourCountsNotOnlyTheSavedOne() {
        var mark = PhotoMark()
        XCTAssertEqual(mark.toggle(.green, shown: mark.shownColour(.kept)), .undecided)
        XCTAssertNil(mark.colour)
    }

    func testClearingTheColourUndecides() {
        var mark = PhotoMark(rating: 2, colourSlug: "red")
        XCTAssertEqual(mark.clearColour(), .undecided)
        XCTAssertNil(mark.colour)
        XCTAssertEqual(mark.rating, 2)
    }

    func testStarsAreClampedAndLeaveTheDecision() {
        var mark = PhotoMark(colourSlug: "red")
        mark.rate(4)
        XCTAssertEqual(mark.rating, 4)
        mark.rate(9)
        XCTAssertEqual(mark.rating, 5)
        mark.rate(-1)
        XCTAssertEqual(mark.rating, 0)
        XCTAssertEqual(mark.colour, .red)
    }

    func testATagGoesOnAndComesOffWhateverItsCase() {
        var mark = PhotoMark(tags: ["Rome"])
        mark.toggle(tag: "rome")
        XCTAssertEqual(mark.tags, [])
        mark.toggle(tag: "Trams")
        XCTAssertEqual(mark.tags, ["Trams"])
    }

    /// The keys match Folders and Bridge's habits: 1-5 stars, 0 clears them, 6-9 colours.
    func testKeys() {
        XCTAssertEqual(TriageLabelKey.command(for: "3"), .stars(3))
        XCTAssertEqual(TriageLabelKey.command(for: "0"), .stars(0))
        XCTAssertEqual(TriageLabelKey.command(for: "6"), .colour(.red))
        XCTAssertEqual(TriageLabelKey.command(for: "8"), .colour(.green))
        XCTAssertEqual(TriageLabelKey.command(for: "9"), .colour(.blue))
        XCTAssertNil(TriageLabelKey.command(for: "x"))
    }
}
