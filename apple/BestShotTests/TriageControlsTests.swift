import XCTest
@testable import BestShot

final class TriageControlsTests: XCTestCase {
    func testEveryControlIsAnIconThatStillSaysWhatItDoes() {
        let spoken = ["Undo", "Skip", "Favourite", "Done", "Bin", "Keep"]
        XCTAssertEqual(Set(TriageControl.allCases.map(\.title)), Set(spoken))
        for control in TriageControl.allCases { XCTAssertFalse(control.symbol.isEmpty, control.title) }
    }

    func testNoTwoControlsLookAlike() {
        XCTAssertEqual(Set(TriageControl.allCases.map(\.symbol)).count, TriageControl.allCases.count)
    }

    func testTheBarRunsFromBinToKeep() {
        XCTAssertEqual(TriageControl.bar, [.bin, .undo, .skip, .favourite, .keep])
    }

    func testFavouriteFillsWhenItsOn() {
        XCTAssertEqual(TriageControl.favourite.symbol(isOn: true), "heart.fill")
        XCTAssertEqual(TriageControl.favourite.symbol(isOn: false), "heart")
        XCTAssertEqual(TriageControl.favourite.title(isOn: true), "Remove favourite")
    }
}
