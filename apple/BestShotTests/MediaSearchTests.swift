import XCTest
@testable import BestShot

final class MediaSearchTests: XCTestCase {
    private func hit(_ query: String, filename: String = "IMG_1.jpg", tags: [String] = [],
                     comment: String = "", project: String? = nil) -> Bool {
        MediaSearch.matches(query, filename: filename, tags: tags, comment: comment, project: project)
    }

    func testNothingTypedMatchesEverything() {
        XCTAssertTrue(hit(""))
        XCTAssertTrue(hit("   "))
    }

    func testFindsFilenamesAndTagsWhateverTheCase() {
        XCTAssertTrue(hit("img_1"))
        XCTAssertTrue(hit("BEACH", tags: ["beach"]))
        XCTAssertFalse(hit("forest", tags: ["beach"]))
    }

    /// All Media prints the project's name under each photo, so it has to find by it.
    func testFindsTheProjectNameShownUnderThePhoto() {
        XCTAssertTrue(hit("wedding", project: "Wedding 2026"))
    }

    func testFindsComments() {
        XCTAssertTrue(hit("favourite", comment: "Dan's favourite"))
    }

    func testEveryWordHasToBeSomewhere() {
        XCTAssertTrue(hit("wedding beach", tags: ["beach"], project: "Wedding 2026"))
        XCTAssertFalse(hit("wedding forest", tags: ["beach"], project: "Wedding 2026"))
    }

    func testAccentsDontStopAMatch() {
        XCTAssertTrue(hit("cafe", tags: ["Café"]))
    }
}
