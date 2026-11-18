import XCTest

@testable import BestShot

/// Organise from a folder in Files: which files come up, and in what order.
final class FolderPhotosTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("DCIM/100APPLE"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ path: String, daysAgo: Double) throws -> URL {
        let url = folder.appendingPathComponent(path)
        try Data([0xFF, 0xD8, 0xFF]).write(to: url)
        let date = Date(timeIntervalSinceNow: -daysAgo * 86_400)
        try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
        return url
    }

    func testPhotosInFoldersWithinComeUpAndNothingElse() throws {
        _ = try file("a.jpg", daysAgo: 3)
        _ = try file("DCIM/100APPLE/IMG_0001.HEIC", daysAgo: 2)
        _ = try file("notes.txt", daysAgo: 1)
        _ = try file(".hidden.jpg", daysAgo: 1)
        let names = FolderPhotos.list(in: folder, order: .oldest).map(\.lastPathComponent)
        XCTAssertEqual(names, ["a.jpg", "IMG_0001.HEIC"])
    }

    func testNewestFirstAndOldestFirst() throws {
        _ = try file("old.jpg", daysAgo: 10)
        _ = try file("new.png", daysAgo: 1)
        XCTAssertEqual(FolderPhotos.list(in: folder, order: .newest).map(\.lastPathComponent), ["new.png", "old.jpg"])
        XCTAssertEqual(FolderPhotos.list(in: folder, order: .oldest).map(\.lastPathComponent), ["old.jpg", "new.png"])
    }

    func testFilesAlreadyOrganisedAreLeftOut() throws {
        let done = try file("done.jpg", daysAgo: 2)
        _ = try file("todo.jpg", daysAgo: 1)
        let names = FolderPhotos.list(in: folder, order: .oldest, excluding: [OrganisedFiles.key(for: done)])
            .map(\.lastPathComponent)
        XCTAssertEqual(names, ["todo.jpg"])
    }
}

/// 17 Nov review: a file filed in a session that ended with Skip or a quit is remembered, so the
/// next session doesn't put it in Photos a second time; Undo of that import forgets it.
final class ImportedFilesTests: XCTestCase {
    func testAFiledFileIsRememberedThenForgotten() {
        let suite = "imported-files-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = URL(fileURLWithPath: "/tmp/DCIM/100APPLE/IMG_0001.JPG")
        XCTAssertNil(ImportedFiles.assetID(for: url, in: defaults))
        ImportedFiles.remember(url, as: "ABC/L0/001", in: defaults)
        XCTAssertEqual(ImportedFiles.assetID(for: URL(fileURLWithPath: "/tmp/DCIM/./100APPLE/IMG_0001.JPG"), in: defaults), "ABC/L0/001")
        ImportedFiles.forget(url, in: defaults)
        XCTAssertNil(ImportedFiles.assetID(for: url, in: defaults))
    }
}

/// 17 Nov review: Undo in Triage took the whole review row away, `organised` and all, so an
/// organised photo came up in Organise again.
final class AssetReviewUndecideTests: XCTestCase {
    func testAnOrganisedRowStaysUndecided() {
        let row = AssetReview(assetLocalID: "a", decision: .kept, organised: true)
        XCTAssertFalse(row.undecide())
        XCTAssertEqual(row.decision, .undecided)
        XCTAssertTrue(row.organised)
    }

    func testARowWithOnlyADecisionGoes() {
        XCTAssertTrue(AssetReview(assetLocalID: "b", decision: .deleted).undecide())
    }
}
