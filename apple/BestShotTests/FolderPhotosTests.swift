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
