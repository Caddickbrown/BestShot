import XCTest
@testable import BestShot

/// Mirrors the Linux app's Rust tests (library.rs, store.rs, cull.rs) so both
/// apps agree on what's in a folder and on `.bestshot-cull.json`.
final class FolderCoreTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bestshot-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func touch(_ rel: String, _ contents: String = "x") throws {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private func exists(_ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(rel).path)
    }

    // MARK: - FolderLibrary

    func testNaturalOrder() {
        let sorted = ["IMG_10.jpg", "img_9.jpg", "IMG_0011.jpg"].sorted(by: FolderLibrary.naturalLess)
        XCTAssertEqual(sorted, ["img_9.jpg", "IMG_10.jpg", "IMG_0011.jpg"])
    }

    func testGroupsLivePhotosAndSidecars() throws {
        for f in ["IMG_0001.HEIC", "IMG_0001.MOV", "IMG_0001.AAE", "IMG_0002.MOV", "notes.txt"] { try touch(f) }

        let items = try FolderLibrary.scan(root: root, recursive: true, includeVideos: true)
        XCTAssertEqual(items.map(\.rel), ["IMG_0001.HEIC", "IMG_0002.MOV"])
        XCTAssertEqual(items[0].kind, .image)
        XCTAssertEqual(items[0].companions, ["IMG_0001.MOV", "IMG_0001.AAE"])
        XCTAssertEqual(items[1].kind, .video)

        // Standalone videos can be excluded, but Live Photo halves stay attached.
        let photosOnly = try FolderLibrary.scan(root: root, recursive: true, includeVideos: false)
        XCTAssertEqual(photosOnly.map(\.rel), ["IMG_0001.HEIC"])
        XCTAssertEqual(photosOnly[0].companions.count, 2)
    }

    func testSkipsHiddenAndRejectDirsAndRespectsRecursion() throws {
        for f in ["a.jpg", "trip/b.jpg", ".hidden/c.jpg", "_Rejected/d.jpg"] { try touch(f) }
        XCTAssertEqual(try FolderLibrary.scan(root: root, recursive: true, includeVideos: true).map(\.rel),
                       ["a.jpg", "trip/b.jpg"])
        XCTAssertEqual(try FolderLibrary.scan(root: root, recursive: false, includeVideos: true).map(\.rel),
                       ["a.jpg"])
    }

    // MARK: - CullStore

    func testStoreRoundTripsAndRecoversFromCorruption() throws {
        var (store, warning) = CullStore.load(from: root)
        XCTAssertNil(warning)
        XCTAssertTrue(store.decisions.isEmpty)

        store.decisions = ["a.jpg": .keep, "sub/b.jpg": .reject]
        store.ranking = ["sub/b.jpg", "a.jpg"]
        try store.save(to: root)
        XCTAssertEqual(CullStore.load(from: root).store, store)

        // Paths keep their slashes unescaped, like the Rust writer.
        let text = try String(contentsOf: CullStore.url(in: root), encoding: .utf8)
        XCTAssertTrue(text.contains("\"sub/b.jpg\""))

        try "{ nope".write(to: CullStore.url(in: root), atomically: true, encoding: .utf8)
        let (fresh, warn) = CullStore.load(from: root)
        XCTAssertTrue(fresh.decisions.isEmpty)
        XCTAssertNotNil(warn)
        XCTAssertTrue(exists(CullStore.fileName + ".corrupt"))
    }

    /// A file written by the Linux app (serde_json pretty output), including
    /// one from before ranking existed.
    func testReadsFilesWrittenByTheLinuxApp() throws {
        let linux = """
        {
          "version": 1,
          "decisions": {
            "Holiday/DSC00001.jpg": "keep",
            "Holiday/DSC00002.jpg": "reject",
            "IMG_0001.JPG": "keep"
          },
          "ranking": [
            "IMG_0001.JPG",
            "Holiday/DSC00001.jpg"
          ]
        }
        """
        let store = try JSONDecoder().decode(CullStore.self, from: Data(linux.utf8))
        XCTAssertEqual(store.decisions["Holiday/DSC00002.jpg"], .reject)
        XCTAssertEqual(store.ranking, ["IMG_0001.JPG", "Holiday/DSC00001.jpg"])

        let old = try JSONDecoder().decode(CullStore.self, from: Data(#"{"version":1,"decisions":{"a.jpg":"keep"}}"#.utf8))
        XCTAssertEqual(old.decisions, ["a.jpg": .keep])
        XCTAssertTrue(old.ranking.isEmpty)
    }

    func testPrunesEntriesForMissingFiles() throws {
        try touch("here.jpg")
        var store = CullStore(decisions: ["here.jpg": .keep, "gone.jpg": .reject], ranking: ["gone.jpg", "here.jpg"])
        XCTAssertTrue(store.pruneMissing(in: root))
        XCTAssertEqual(store.decisions, ["here.jpg": .keep])
        XCTAssertEqual(store.ranking, ["here.jpg"])
        XCTAssertFalse(store.pruneMissing(in: root))
    }

    // MARK: - Culler

    func testFolderModeMovesItemWithCompanionsPreservingLayout() throws {
        for f in ["trip/IMG_1.HEIC", "trip/IMG_1.MOV", "trip/IMG_2.JPG"] { try touch(f, "data") }
        // A name clash already waiting in the reject folder.
        try touch("_Rejected/trip/IMG_1.HEIC", "old")

        let items = try FolderLibrary.scan(root: root, recursive: true, includeVideos: true)
        let reject = items.filter { $0.rel == "trip/IMG_1.HEIC" }
        let out = Culler.apply(root: root, rejects: reject, mode: .folder)

        XCTAssertEqual(out.items, 1)
        XCTAssertEqual(out.files, 2)
        XCTAssertEqual(out.bytes, 8)
        XCTAssertTrue(out.failed.isEmpty)
        XCTAssertFalse(exists("trip/IMG_1.HEIC"))
        XCTAssertFalse(exists("trip/IMG_1.MOV"))
        XCTAssertTrue(exists("trip/IMG_2.JPG"))
        XCTAssertTrue(exists("_Rejected/trip/IMG_1 (1).HEIC"))
        XCTAssertTrue(exists("_Rejected/trip/IMG_1.MOV"))
        // The reject folder is never rescanned.
        XCTAssertEqual(try FolderLibrary.scan(root: root, recursive: true, includeVideos: true).count, 1)
    }
}
