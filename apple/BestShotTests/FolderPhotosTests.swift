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

    /// Review L54: a new card reuses DCIM/100APPLE/IMG_0001. A file organised before is known by
    /// what it is (size and date), not by its path alone, so the new photo there comes up.
    func testANewPhotoAtAnOrganisedPathComesUp() throws {
        let suite = "organised-files-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = try file("DCIM/100APPLE/IMG_0001.JPG", daysAgo: 30)
        OrganisedFiles.mark(url, in: defaults)
        XCTAssertEqual(FolderPhotos.list(in: folder, order: .oldest, excluding: OrganisedFiles.done(in: defaults)), [])
        try Data(repeating: 0xAB, count: 4_096).write(to: url)   // the next card's IMG_0001
        XCTAssertEqual(FolderPhotos.list(in: folder, order: .oldest, excluding: OrganisedFiles.done(in: defaults))
                        .map(\.lastPathComponent), ["IMG_0001.JPG"])
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

/// Review L54: the photo imported from a reused card path is a new photo, not the old one.
final class ImportedFilesFingerprintTests: XCTestCase {
    func testAnotherFileAtTheSamePathIsNotTheImportedOne() throws {
        let suite = "imported-fp-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("IMG_0001.JPG")
        try Data([0xFF, 0xD8, 0xFF]).write(to: url)
        ImportedFiles.remember(url, as: "ABC/L0/001", in: defaults)
        XCTAssertEqual(ImportedFiles.assetID(for: url, in: defaults), "ABC/L0/001")
        try Data(repeating: 0xAB, count: 4_096).write(to: url)
        XCTAssertNil(ImportedFiles.assetID(for: url, in: defaults), "the new card's photo would never be added")
    }

    func testAnEntryFromBeforeFingerprintsStillCounts() {
        let suite = "imported-old-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = URL(fileURLWithPath: "/tmp/DCIM/100APPLE/IMG_0009.JPG")
        defaults.set([OrganisedFiles.key(for: url): "OLD/L0/001"], forKey: "organise.filesImported")
        XCTAssertEqual(ImportedFiles.assetID(for: url, in: defaults), "OLD/L0/001")
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
