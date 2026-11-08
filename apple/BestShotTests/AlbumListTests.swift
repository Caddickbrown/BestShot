import XCTest
@testable import BestShot

/// PhotoKit gives one collection per album, and a library can hold several with
/// the same name. Plain structs stand in for `PHAssetCollection`, which can't be made here.
final class AlbumListTests: XCTestCase {
    private struct Album: Equatable {
        let id: String
        let title: String?
        var count = 0
    }

    private func unique(_ albums: [Album]) -> [String] {
        AlbumList.unique(albums, title: \.title, count: \.count).map(\.id)
    }

    func testTwoAlbumsWithOneNameShowOnce() {
        XCTAssertEqual(unique([Album(id: "a", title: "Holiday"), Album(id: "b", title: "Holiday")]), ["a"])
    }

    func testTheOneWithTheMostPhotosIsTheOneKept() {
        XCTAssertEqual(unique([Album(id: "a", title: "Holiday", count: 2), Album(id: "b", title: "Holiday", count: 40)]), ["b"])
    }

    func testCaseAndStraySpacesDontMakeANewName() {
        XCTAssertEqual(unique([Album(id: "a", title: "Holiday"), Album(id: "b", title: " holiday ")]), ["a"])
    }

    func testDifferentNamesAllStayInOrder() {
        let albums = [Album(id: "b", title: "Zebra"), Album(id: "a", title: "Apple"), Album(id: "c", title: "Album 10"), Album(id: "d", title: "Album 2")]
        XCTAssertEqual(unique(albums), ["d", "c", "a", "b"])
    }

    func testAlbumsWithNoNameAreNeverTakenForEachOther() {
        XCTAssertEqual(unique([Album(id: "a", title: nil), Album(id: "b", title: nil)]).count, 2)
    }

    func testANewAlbumNameFindsTheOneAlreadyThere() {
        let albums = [Album(id: "a", title: "Holiday"), Album(id: "b", title: "Work")]
        XCTAssertEqual(AlbumList.existing(named: " holiday", in: albums, title: \.title)?.id, "a")
        XCTAssertNil(AlbumList.existing(named: "Dogs", in: albums, title: \.title))
    }

    // MARK: Folders

    private struct Filed {
        let id: String
        let title: String?
        let folder: String?
    }

    func testOneNameInTwoFoldersKeepsBoth() {
        let albums = [Filed(id: "a", title: "Lisbon", folder: nil), Filed(id: "b", title: "Lisbon", folder: "Imported from Google")]
        let kept = AlbumList.unique(albums, title: \.title, count: { _ in 0 }, folder: \.folder).map(\.id)
        XCTAssertEqual(kept, ["a", "b"], "the top-level one first, then by folder")
    }

    func testOneNameTwiceInOneFolderStillShowsOnce() {
        let albums = [Filed(id: "a", title: "Lisbon", folder: "Imported from Google"), Filed(id: "b", title: "lisbon", folder: "Imported from Google")]
        XCTAssertEqual(AlbumList.unique(albums, title: \.title, count: { _ in 0 }, folder: \.folder).map(\.id), ["a"])
    }

    func testTheLabelNamesTheFolder() {
        XCTAssertEqual(AlbumList.label(title: "Lisbon", folder: "Imported from Google"), "Lisbon · Imported from Google")
        XCTAssertEqual(AlbumList.label(title: "Lisbon", folder: nil), "Lisbon")
    }

    func testANewNameFilesIntoTheTopLevelTwinFirst() {
        let albums = [Filed(id: "g", title: "Lisbon", folder: "Imported from Google"), Filed(id: "t", title: "Lisbon", folder: nil)]
        XCTAssertEqual(AlbumList.existing(named: "lisbon", in: albums, title: \.title, folder: \.folder)?.id, "t")
        XCTAssertEqual(AlbumList.existing(named: "lisbon", in: [albums[0]], title: \.title, folder: \.folder)?.id, "g")
    }
}
