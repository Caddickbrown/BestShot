import XCTest
import SwiftUI
@testable import BestShot

private final class Media: RankMedia {
    func thumbnail(_ id: String) -> AnyView { AnyView(Color.gray) }
    func fullImage(_ id: String) -> AnyView { AnyView(Color.gray) }
    func caption(_ id: String) -> String { id }
}

/// Monitor Mode, 18 Nov: everything the phone does to projects and imported
/// photos can be done from the monitor, by ⌘K and a key, with the phone's
/// alerts as questions in the palette.
@MainActor
final class MonitorProjectsTests: XCTestCase {
    private var library: FakeMonitorLibrary!
    private var desk: MonitorDesk!
    private var opened: [String] = []
    private var said: [String] = []
    private var undos: [() -> Void] = []
    private let wedding = UUID()

    override func setUp() async throws {
        library = FakeMonitorLibrary()
        library.projects = [(wedding, "Wedding", 3)]
        library.items = [
            MonitorMediaItem(id: "a", title: "beach.jpg", detail: "", tags: ["sea"], rank: 1, size: 10,
                             imported: Date(timeIntervalSince1970: 300), project: "Wedding"),
            MonitorMediaItem(id: "b", title: "cake.jpg", detail: "", tags: [], note: "the big one", rank: 0, size: 30,
                             imported: Date(timeIntervalSince1970: 100), project: "Wedding"),
            MonitorMediaItem(id: "c", title: "dance.mov", detail: "", tags: [], isVideo: true, size: 20,
                             imported: Date(timeIntervalSince1970: 200), project: "Wedding"),
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("marks.json")
        desk = MonitorDesk(library: library, marks: PhotoMarkStore(url: url))
        desk.isConnected = true
        desk.setLocked(false)
        desk.onCommand = { [unowned self] in opened.append($0) }
        desk.onSay = { [unowned self] in said.append($0) }
        desk.onUndoable = { [unowned self] text, undo in
            said.append(text)
            undos.append(undo)
        }
    }

    private func press(_ key: KeyName, _ mods: KeyMods = []) { desk.handle(MonitorPress(key, mods)) }
    private func type(_ text: String) { for c in text { desk.handle(.typed(c)) } }
    private var menu: CommandPalette<BestShotCommandList> { MonitorMenu(desk) }
    private var ids: Set<String> { Set(menu.rows.map(\.id)) }

    /// Opens the row's step in the palette, as the key or a tap does.
    private func open(_ id: String) -> CommandPalette<BestShotCommandList> {
        var m = menu
        XCTAssertEqual(m.choose(id), .stay, "\(id) opens a step")
        return m
    }

    private func openWedding() {
        desk.run(.project(wedding))
        XCTAssertEqual(desk.pane, .media(project: wedding))
    }

    // MARK: Projects

    func testNewProjectFromTheProjectsListByKeyAndMenu() {
        desk.run(.go(.projects))
        press(.char("n"))
        XCTAssertEqual(opened, ["project.new"], "n opens New project… in the palette")
        var m = open("project.new")
        m.type("Holiday")
        guard case .run(let action) = m.press(.enter) else { return XCTFail("makes it") }
        desk.run(action)
        XCTAssertTrue(library.projects.contains { $0.name == "Holiday" })
        XCTAssertEqual(desk.litRow?.title, "Holiday", "the new project is lit")
        XCTAssertTrue(said.last?.contains("Holiday") ?? false)
    }

    func testRenameTheLitProject() {
        desk.run(.go(.projects))
        press(.down) // past All Media, onto Wedding
        XCTAssertEqual(desk.litRow?.title, "Wedding")
        press(.char("r"))
        XCTAssertEqual(opened, ["project.rename"])
        var m = open("project.rename")
        XCTAssertEqual(m.query, "Wedding", "starts from the name")
        _ = m.press(.clear)
        m.type("Our wedding")
        guard case .run(let action) = m.press(.enter) else { return XCTFail("renames") }
        XCTAssertEqual(action, .renameProject(wedding, "Our wedding"))
        desk.run(action)
        XCTAssertEqual(library.projects.first?.name, "Our wedding")
    }

    func testDeleteAProjectAsksInThePalette() async {
        openWedding()
        press(.backspace, .command)
        XCTAssertEqual(opened, ["project.delete"])
        var m = open("project.delete")
        XCTAssertTrue(m.isConfirming, "a question in the palette, not the phone's alert")
        XCTAssertTrue(library.removed.isEmpty)
        guard case .run(let action) = m.press(.enter) else { return XCTFail("Return confirms") }
        desk.run(action)
        await desk.work?.value
        XCTAssertEqual(library.removed, [wedding])
        XCTAssertEqual(desk.pane, .projects, "off the project that's gone")
    }

    func testEscBacksOutOfTheDeleteQuestion() {
        openWedding()
        var m = open("project.delete")
        _ = m.press(.esc)
        XCTAssertFalse(m.isConfirming)
        XCTAssertTrue(library.removed.isEmpty)
    }

    // MARK: Sort, show, find

    func testSortShowAndFind() {
        openWedding()
        XCTAssertEqual(desk.mediaItems.map(\.id), ["b", "a", "c"], "a project starts by rank, as on the phone")
        press(.char("s"))
        press(.char("f"))
        XCTAssertEqual(opened, ["project.sort", "project.filter"])
        desk.run(.projectSort(.sizeLargest))
        XCTAssertEqual(desk.mediaItems.map(\.id), ["b", "c", "a"])
        desk.run(.projectFilter(.videos))
        XCTAssertEqual(desk.mediaItems.map(\.id), ["c"])
        desk.run(.projectFilter(.all))
        var m = open("media.find")
        m.type("big")
        guard case .run(let action) = m.press(.enter) else { return XCTFail("finds") }
        desk.run(action)
        XCTAssertEqual(desk.mediaItems.map(\.id), ["b"], "notes are searched, as on the phone")
        XCTAssertTrue(ids.contains("media.findoff"))
        desk.run(.findMedia(""))
        XCTAssertEqual(desk.mediaItems.count, 3)
    }

    func testAllMediaStartsNewestFirst() {
        desk.run(.go(.allMedia))
        XCTAssertEqual(desk.mediaItems.map(\.id), ["a", "c", "b"])
        XCTAssertTrue(ids.isSuperset(of: ["project.sort", "project.filter", "media.find"]))
        XCTAssertFalse(ids.contains("project.delete"), "All Media isn't a project")
    }

    // MARK: Tags and notes

    func testTagsAreTicksWithNewOnesTypedIn() {
        openWedding()
        press(.down) // the lit row is "a", beach.jpg
        XCTAssertEqual(desk.litRow?.id, "a")
        press(.char("t"))
        XCTAssertEqual(opened, ["media.tags"])
        var m = open("media.tags")
        XCTAssertTrue(m.isTicking)
        m.type("party")
        _ = m.press(.enter) // adds it, ticked
        guard case .run(let action) = m.press(.done) else { return XCTFail("Done") }
        XCTAssertEqual(action, .setMediaTags("a", ["sea", "party"]))
        desk.run(action)
        XCTAssertEqual(desk.mediaAll.first { $0.id == "a" }?.tags, ["sea", "party"])
    }

    func testNotesOnTheOpenPhotoAndSlideshow() {
        openWedding()
        press(.enter) // opens "b", the first by rank
        XCTAssertEqual(desk.pane, .mediaPhoto(project: wedding))
        press(.char("e"))
        XCTAssertEqual(opened, ["media.note"])
        var m = open("media.note")
        XCTAssertEqual(m.query, "the big one")
        _ = m.press(.clear)
        m.type("cut it")
        guard case .run(let action) = m.press(.enter) else { return XCTFail("saves") }
        desk.run(action)
        XCTAssertEqual(library.mediaNotes["b"], "cut it")
        XCTAssertEqual(desk.mediaItems[desk.mediaIndex].id, "b", "the same photo stays up")
        desk.run(.noteMedia("b", ""))
        XCTAssertEqual(said.last, "Note cleared.")
        undos.last?()
        XCTAssertEqual(library.mediaNotes["b"], "cut it", "Undo puts it back")
        press(.char("p"))
        XCTAssertTrue(desk.slideshow)
        XCTAssertEqual(menu.rows.first { $0.id == "media.slideshow" }?.title, "Stop slideshow")
        press(.char("p"))
        XCTAssertFalse(desk.slideshow)
    }

    // MARK: Compare

    func testCompareAProjectThenStopWithoutSaving() {
        var saved: [[String]] = []
        library.projectBoards[wedding] = RankBoard(title: "Wedding", media: Media(),
                                                   pools: [RankPool(id: "p", title: "Wedding", ids: ["b", "a", "c"])],
                                                   ranking: ["b", "a"], persist: { saved.append($0) })
        openWedding()
        press(.char("c"))
        XCTAssertEqual(desk.pane, .rankCompare)
        desk.handle(MonitorPress(.left))
        var m = menu
        m.type("stop without saving")
        _ = m.press(.enter)
        XCTAssertTrue(m.isConfirming)
        guard case .run(let action) = m.press(.enter) else { return XCTFail("confirms") }
        desk.run(action)
        XCTAssertEqual(desk.pane, .media(project: wedding), "back to the project's photos")
        XCTAssertEqual(saved, [], "nothing kept")
        XCTAssertNil(desk.projectBoard)
    }

    func testCompareAProjectAndEscSaves() {
        var saved: [[String]] = []
        library.projectBoards[wedding] = RankBoard(title: "Wedding", media: Media(),
                                                   pools: [RankPool(id: "p", title: "Wedding", ids: ["b", "a", "c"])],
                                                   ranking: [], persist: { saved.append($0) })
        openWedding()
        desk.run(.compareProject(.all))
        desk.handle(MonitorPress(.left))
        press(.escape)
        XCTAssertEqual(desk.pane, .media(project: wedding))
        XCTAssertEqual(saved.count, 1)
    }

    func testClearProjectRankingsAsks() {
        openWedding()
        var m = open("project.clearranks")
        XCTAssertTrue(m.isConfirming)
        guard case .run(let action) = m.press(.enter) else { return XCTFail("confirms") }
        desk.run(action)
        XCTAssertEqual(library.clearedRankings, [wedding])
    }

    func testImportsFinishOnThePhone() {
        openWedding()
        let rows = menu.rows
        XCTAssertNotNil(rows.first { $0.id == "project.importphotos" }?.onPhone)
        XCTAssertNotNil(rows.first { $0.id == "project.importfiles" }?.onPhone)
    }

    // MARK: Rank, Triage, keys

    func testClearRankingIsUndoneByCommandZ() async {
        let board = RankBoard(title: "t", media: Media(), pools: [RankPool(id: "p", title: "Kept", ids: ["x", "y"])],
                              ranking: ["y", "x"], persist: { _ in })
        library.board = board
        desk.run(.go(.rank))
        await desk.work?.value
        desk.run(.clearRanking)
        XCTAssertEqual(board.ranked, [])
        XCTAssertEqual(said.last, "Ranking cleared.", "a notice with Undo, on the monitor")
        press(.char("z"), .command)
        XCTAssertEqual(board.ranked, ["y", "x"])
    }

    func testPurpleHasAKey() {
        library.triageIDs = ["a", "b"]
        press(.enter) // Resume Triage
        XCTAssertEqual(desk.pane, .loupe)
        press(.char("p"))
        XCTAssertEqual(desk.colour("a"), .purple)
        XCTAssertTrue(desk.keys.contains { $0.keys == "p" && $0.label == "Purple" })
    }

    func testTagWhatYouKeepStartsTheRunWithThem() async {
        library.nextSession = ["a", "b"]
        desk.run(.go(.triage))
        var m = open("triage.runtags")
        m.type("trip, sea")
        guard case .run(let action) = m.press(.enter) else { return XCTFail("sets them") }
        desk.run(action)
        desk.run(.startTriage(.allPhotos))
        await desk.work?.value
        XCTAssertEqual(library.startedWithTags, ["trip", "sea"])
    }

    func testPhotosWaitingFromARunThatEndedEarly() async {
        library.waitingDeletes = 3
        desk.run(.go(.triage))
        XCTAssertTrue(ids.contains("triage.waiting.keep"))
        var m = open("triage.waiting.delete")
        XCTAssertTrue(m.isConfirming)
        XCTAssertNotNil(menu.rows.first { $0.id == "triage.waiting.delete" }?.onPhone, "Photos asks on the phone")
        guard case .run(let action) = m.press(.enter) else { return XCTFail("confirms") }
        desk.run(action)
        await desk.work?.value
        XCTAssertEqual(library.deletedWaiting, 3)
        XCTAssertFalse(ids.contains("triage.waiting.keep"))
    }

    func testEveryCommandTheMonitorListsRunsThere() {
        // The audit's rule: nothing left off the monitor that the phone offers on these screens.
        desk.run(.go(.projects))
        XCTAssertTrue(ids.contains("project.new"))
        openWedding()
        for id in ["project.compareall", "project.importphotos", "project.importfiles", "project.sort", "project.filter",
                   "media.find", "project.clearranks", "project.rename", "project.delete"] {
            XCTAssertTrue(ids.contains(id), id)
        }
        for row in menu.rows {
            XCTAssertEqual(CommandSafety.unguarded([row]).count, 0, row.title)
            XCTAssertEqual(CommandSafety.unmarked([row]).count, 0, row.title)
        }
    }
}
