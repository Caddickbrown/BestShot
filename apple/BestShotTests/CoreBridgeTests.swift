import XCTest
@testable import BestShot

/// Exercises the Rust core through the generated Swift bindings. The logic
/// itself is tested in Rust (`cargo test` in core/); these prove the
/// XCFramework links and the Swift-facing API behaves.
final class CoreBridgeTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bestshot-core-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func touch(_ rel: String) throws {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("data".utf8).write(to: url)
    }

    private func exists(_ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(rel).path)
    }

    func testScanStoreAndCullInAFolder() throws {
        for f in ["trip/IMG_1.HEIC", "trip/IMG_1.MOV", "trip/IMG_2.JPG", "_Rejected/old.jpg"] { try touch(f) }

        let items = try scanFolder(root: root.path, recursive: true, includeVideos: true)
        XCTAssertEqual(items.map(\.rel), ["trip/IMG_1.HEIC", "trip/IMG_2.JPG"])
        XCTAssertEqual(items[0].companions, ["trip/IMG_1.MOV"])
        XCTAssertEqual(items[0].filename, "IMG_1.HEIC")

        var store = loadStore(root: root.path).store
        XCTAssertEqual(store, .empty)
        store.decisions["trip/IMG_1.HEIC"] = .reject
        store.ranking = ["trip/IMG_2.JPG"]
        try saveStore(root: root.path, store: store)
        XCTAssertEqual(loadStore(root: root.path).store, store)

        let out = applyCull(root: root.path, rejects: [items[0]], mode: .folder, trasher: FileManagerTrasher())
        XCTAssertEqual(out.items, 1)
        XCTAssertEqual(out.files, 2)
        XCTAssertTrue(exists("_Rejected/trip/IMG_1.HEIC"))
        XCTAssertTrue(exists("_Rejected/trip/IMG_1.MOV"))
    }

    /// The file format is the Linux app's: a store it wrote must load here.
    func testReadsAStoreWrittenByTheLinuxApp() throws {
        try touch("IMG_0001.JPG")
        try touch("Holiday/DSC00001.jpg")
        let linux = """
        {
          "version": 1,
          "decisions": {
            "Holiday/DSC00001.jpg": "keep",
            "IMG_0001.JPG": "reject"
          },
          "ranking": [
            "Holiday/DSC00001.jpg"
          ]
        }
        """
        try linux.write(to: root.appendingPathComponent(".bestshot-cull.json"), atomically: true, encoding: .utf8)
        let loaded = loadStore(root: root.path)
        XCTAssertNil(loaded.warning)
        XCTAssertEqual(loaded.store.decisions, ["Holiday/DSC00001.jpg": .keep, "IMG_0001.JPG": .reject])
        XCTAssertEqual(loaded.store.ranking, ["Holiday/DSC00001.jpg"])
    }

    func testColourLabelsThroughTheCatalog() throws {
        try touch("a.jpg")
        try touch("b.jpg")
        let settings = loadLabelSettings(path: root.appendingPathComponent("labels.json").path).settings
        let catalog = try FolderCatalog.open(root: root.path, recursive: true, includeVideos: true, settings: settings, writeJpeg: false)

        let row = try catalog.toggleColour(rel: "a.jpg", colour: .red).row
        XCTAssertEqual(row.decision, .reject)
        XCTAssertTrue(exists("a.xmp"))
        XCTAssertEqual(catalog.rejects().map(\.rel), ["a.jpg"])

        _ = try catalog.setRating(rel: "b.jpg", stars: 4)
        let filter = FolderFilter(status: .all, stars: .atLeast(stars: 3), labels: [], keywords: [], anyKeyword: false)
        XCTAssertEqual(catalog.query(filter: filter, sort: .name), [1])

        let out = catalog.applyCull(mode: .folder, trasher: FileManagerTrasher())
        XCTAssertEqual(out.files, 2)
        XCTAssertTrue(exists("_Rejected/a.xmp"))
    }

    func testRankSessionRanksAndUndoes() {
        let truth = ["a", "b", "c", "d", "e"]
        let session = RankSession(ids: truth.reversed(), ranking: [], scope: .all)
        var answered = 0
        while let pair = session.currentPair() {
            let leftBetter = truth.firstIndex(of: pair.left)! < truth.firstIndex(of: pair.right)!
            session.choose(choice: leftBetter ? .left : .right)
            answered += 1
        }
        XCTAssertEqual(session.order(), truth)
        let progress = session.progress()
        XCTAssertTrue(progress.finished)
        XCTAssertEqual(progress.percent, 100)
        XCTAssertEqual(Int(progress.asked), answered)

        XCTAssertTrue(session.undo())
        XCTAssertNotNil(session.currentPair())
    }
}
