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
