import SwiftData
import XCTest

@testable import BestShot

/// Deleting a project takes the project only: its photos are moved to Files,
/// never deleted, and nothing outside it is touched.
@MainActor
final class ProjectLibraryTests: XCTestCase {
    private var root: URL!
    private var store: MediaStore!
    private var container: ModelContainer!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = MediaStore(base: root.appendingPathComponent("Support"), documents: root.appendingPathComponent("Documents"))
        container = try ModelContainer(for: Project.self, MediaItem.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDeletingAProjectMovesItsPhotosToFilesAndLeavesOthersAlone() throws {
        let context = container.mainContext
        let doomed = Project(name: "Holiday: Rome")
        let other = Project(name: "Other")
        context.insert(doomed)
        context.insert(other)
        let photo = Data([1, 2, 3, 4])
        _ = try store.storeMedia(data: photo, preferredName: "IMG_1.jpg", projectID: doomed.uuid)
        _ = try store.storeThumbnail(data: photo, filename: "IMG_1.jpg", projectID: doomed.uuid)
        let otherPath = try store.storeMedia(data: photo, preferredName: "IMG_2.jpg", projectID: other.uuid).relativePath
        try context.save()

        let kept = try XCTUnwrap(ProjectLibrary.remove(doomed, context: context, store: store))

        XCTAssertEqual(kept.lastPathComponent, "Holiday- Rome")
        XCTAssertEqual(kept.deletingLastPathComponent(), store.removedRoot)
        XCTAssertEqual(try Data(contentsOf: kept.appendingPathComponent("IMG_1.jpg")), photo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.mediaRoot.appendingPathComponent(doomed.uuid.uuidString).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.thumbRoot.appendingPathComponent(doomed.uuid.uuidString).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.absoluteMediaURL(for: otherPath).path))
        let left = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(left.map(\.name), ["Other"])
    }

    func testTwoDeletedProjectsWithOneNameKeepBothFolders() throws {
        let context = container.mainContext
        for _ in 0..<2 {
            let project = Project(name: "Trip")
            context.insert(project)
            _ = try store.storeMedia(data: Data([9]), preferredName: "a.jpg", projectID: project.uuid)
            try ProjectLibrary.remove(project, context: context, store: store)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: store.removedRoot.path).sorted()
        XCTAssertEqual(names, ["Trip", "Trip (1)"])
    }

    func testAnEmptyProjectLeavesNothingBehind() throws {
        let context = container.mainContext
        let project = Project(name: "Empty")
        context.insert(project)
        XCTAssertNil(try ProjectLibrary.remove(project, context: context, store: store))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.removedRoot.path))
    }

    func testRenamingTrimsAndRefusesBlank() throws {
        let context = container.mainContext
        let project = Project(name: "Old")
        context.insert(project)
        XCTAssertFalse(ProjectLibrary.rename(project, to: "   ", context: context))
        XCTAssertEqual(project.name, "Old")
        XCTAssertTrue(ProjectLibrary.rename(project, to: "  New name ", context: context))
        XCTAssertEqual(project.name, "New name")
    }
}
