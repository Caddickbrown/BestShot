import XCTest
@testable import BestShot

final class PhotoSourceTests: XCTestCase {
    func testScreenshotsIsNearTheTopNotInAMenu() {
        XCTAssertEqual(Array(TriageSourceOption.quick.prefix(2)), [.allPhotos, .smart(.screenshots)])
    }

    func testEverySourceHasANameAndAnIcon() {
        for source in TriageSourceOption.quick {
            XCTAssertFalse(source.title.isEmpty)
            XCTAssertFalse(source.symbol.isEmpty)
        }
    }

    func testNoSourceIsListedTwice() {
        XCTAssertEqual(Set(TriageSourceOption.quick).count, TriageSourceOption.quick.count)
    }
}

/// Photos gives apps no hidden photo while Settings › Apps › Photos › Use Face ID
/// is on (the default since iOS 16), even with includeHiddenAssets: Hidden just
/// counts 0. So a 0 for Hidden says why rather than claiming there are none.
final class HiddenCountTests: XCTestCase {
    func testHiddenAtZeroShowsNoNumberButSaysWhy() {
        let hidden = TriageSourceOption.smart(.hidden)
        XCTAssertNil(hidden.countText(0))
        XCTAssertEqual(hidden.countNote(0), TriageSourceOption.hiddenLockedNote)
        XCTAssertTrue(TriageSourceOption.hiddenLockedNote.contains("Use Face ID"))
    }

    func testHiddenWithPhotosShowsItsCount() {
        let hidden = TriageSourceOption.smart(.hidden)
        XCTAssertEqual(hidden.countText(12), "12")
        XCTAssertNil(hidden.countNote(12))
    }

    func testOtherSourcesShowZeroAsZero() {
        XCTAssertEqual(TriageSourceOption.screenshots.countText(0), "0")
        XCTAssertNil(TriageSourceOption.screenshots.countNote(0))
        XCTAssertNil(TriageSourceOption.allPhotos.countText(nil))
    }

    func testAnEmptyHiddenSessionSaysWhy() {
        let fallback = "No unreviewed photos found for this source."
        XCTAssertEqual(TriageSourceOption.screenshots.nothingFound(fallback), fallback)
        XCTAssertTrue(TriageSourceOption.smart(.hidden).nothingFound(fallback).contains("Use Face ID"))
    }
}
