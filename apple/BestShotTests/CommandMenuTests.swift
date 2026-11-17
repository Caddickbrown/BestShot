import XCTest
import SwiftUI
@testable import BestShot

/// The ⌘K menu as the app builds it: from `MonitorDesk.commandState` on the
/// monitor, from `BestShotCommandState.phone` on the phone, then the kit's palette.
@MainActor
enum DeskMenu {
    static func make(_ desk: MonitorDesk) -> CommandPalette<BestShotCommandList> {
        CommandPalette(BestShotCommandList(state: desk.commandState()))
    }

    /// Types, presses Return, and runs what that chose on the monitor.
    @discardableResult
    static func choose(_ text: String, on desk: MonitorDesk) -> BestShotCommand? {
        var menu = make(desk)
        menu.type(text)
        guard case .run(let action) = menu.press(.enter) else { return nil }
        desk.run(action)
        return action
    }
}

/// `MonitorMenu(desk)` for the palette, as the tests elsewhere use it.
@MainActor
func MonitorMenu(_ desk: MonitorDesk) -> CommandPalette<BestShotCommandList> { DeskMenu.make(desk) }

private final class Media: RankMedia {
    func thumbnail(_ id: String) -> AnyView { AnyView(Color.gray) }
    func fullImage(_ id: String) -> AnyView { AnyView(Color.gray) }
    func caption(_ id: String) -> String { id }
}

@MainActor
final class CommandMenuTests: XCTestCase {
    private var library: FakeMonitorLibrary!
    private var marks: PhotoMarkStore!
    private var desk: MonitorDesk!

    override func setUp() async throws {
        library = FakeMonitorLibrary()
        library.triageIDs = ["a", "b", "c", "d"]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("marks.json")
        marks = PhotoMarkStore(url: url)
        desk = MonitorDesk(library: library, marks: marks)
        desk.isConnected = true
        desk.setLocked(false)
        desk.handle(MonitorPress(.enter)) // Resume Triage: the loupe, on "a".
        XCTAssertEqual(desk.current, "a")
    }

    private func rows(_ state: BestShotCommandState) -> [CommandRow<BestShotCommand>] {
        BestShotCommandList(state: state).rows(stage: nil, typing: false)
    }

    private func everything(_ state: BestShotCommandState) -> [CommandRow<BestShotCommand>] {
        rows(state).flatMap { [$0] + $0.underneath }
    }

    private func phone(_ place: AppCommands.Place, project: BestShotCommandState.OpenProject? = nil,
                       rank: RankBoard? = nil) -> BestShotCommandState {
        .phone(place: place, project: project, library: library, marks: marks, rank: rank,
               defaults: UserDefaults(suiteName: "commands-\(UUID().uuidString)")!)
    }

    // MARK: Safety, everywhere the menu can be

    private var states: [BestShotCommandState] {
        var project = BestShotCommandState.OpenProject(id: UUID(), name: "Wedding", count: 5, unranked: 2)
        project.selecting = true
        project.selected = 3
        project.canJoin = true
        let board = RankBoard(title: "t", media: Media(), pools: [RankPool(id: "p", title: "Kept", ids: ["a", "b", "c"])],
                              ranking: ["a", "b"], persist: { _ in })
        library.organisePhoto = "o1"
        library.organiseAlbums = [("a1", "Lisbon", false), ("a2", "Kids", true)]
        defer { library.organisePhoto = nil }
        return [desk.commandState(), phone(.triage), phone(.project(project.id), project: project), phone(.organise),
                phone(.rank, rank: board), phone(.home), phone(.organise)]
    }

    func testNothingDestroysWithoutAWayBack() {
        for state in states {
            XCTAssertEqual(CommandSafety.unguarded(rows(state)).map(\.title), [], "\(state.screen)")
            XCTAssertEqual(CommandSafety.unmarked(rows(state)).map(\.title), [], "\(state.screen)")
        }
    }

    func testDeletesAreRed() {
        let id = UUID()
        let project = BestShotCommandState.OpenProject(id: id, name: "Wedding", count: 5, selecting: true, selected: 2)
        let all = everything(phone(.project(id), project: project))
        for title in ["Delete project…", "Delete the chosen…", "Clear rankings…"] {
            let row = all.first { $0.title == title }
            XCTAssertEqual(row?.destructive, true, title)
            XCTAssertEqual(row?.confirms, true, "\(title) asks first, as its button does")
        }
        let bin = everything(phone(.triage)).first { $0.id == "photo.bin" }
        XCTAssertEqual(bin?.destructive, true)
        XCTAssertEqual(bin?.undoable, true)
    }

    // MARK: No cap, and the photo first

    func testTheListScrollsPastTen() {
        let menu = MonitorMenu(desk)
        XCTAssertGreaterThan(menu.rows.count, CommandPaletteLimit.rows, "every command is there, not the first ten")
        XCTAssertTrue(menu.rows.contains { $0.id == "go.6" }, "Settings, far down, is still listed")
    }

    func testThePhotoOnScreenComesFirst() {
        let menu = MonitorMenu(desk)
        XCTAssertEqual(menu.sections.first?.title, "This photo")
        let titles = menu.sections.first?.rows.map(\.title) ?? []
        for title in ["Stars…", "Mark green", "Mark red", "Favourite", "Tag…", "Zoom in", "Compare with the next photo"] {
            XCTAssertTrue(titles.contains(title), title)
        }
    }

    // MARK: The photo on the monitor

    func testColoursStarsFavouriteAndTagsFromTheMenu() {
        DeskMenu.choose("mark green", on: desk)
        XCTAssertEqual(desk.colour("a"), .green)
        XCTAssertEqual(library.decision("a"), .kept)
        XCTAssertEqual(MonitorMenu(desk).rows.first { $0.id == "photo.colour.green" }?.title, "Take green off",
                       "a toggle says which way it goes")

        var menu = MonitorMenu(desk)
        menu.type("stars")
        XCTAssertEqual(menu.lit?.id, "photo.stars")
        _ = menu.press(.enter)
        menu.type("3")
        guard case .run(let three) = menu.press(.enter) else { return XCTFail("a pick") }
        desk.run(three)
        XCTAssertEqual(marks.mark("a").rating, 3)

        DeskMenu.choose("favourite", on: desk)
        XCTAssertEqual(library.favourites, 1)

        menu = MonitorMenu(desk)
        menu.type("tag…")
        _ = menu.press(.enter)
        XCTAssertTrue(menu.isAsking)
        menu.type("beach")
        guard case .run(let tag) = menu.press(.enter) else { return XCTFail("a tag") }
        desk.run(tag)
        XCTAssertEqual(marks.mark("a").tags, ["beach"])
        XCTAssertTrue(MonitorMenu(desk).rows.contains { $0.title == "Take tag “beach” off" })
    }

    func testCompareZoomAndInfo() {
        DeskMenu.choose("compare with", on: desk)
        XCTAssertEqual(desk.pinned, "a")
        XCTAssertTrue(MonitorMenu(desk).rows.contains { $0.title == "Stop comparing" })
        DeskMenu.choose("swap sides", on: desk)
        XCTAssertEqual(desk.pinned, "b")
        DeskMenu.choose("zoom in", on: desk)
        XCTAssertEqual(desk.zoom, 2)
        DeskMenu.choose("show photo info", on: desk)
        XCTAssertTrue(desk.showInfo)
    }

    func testTwoTagFiltersAtOnce() {
        marks.set(PhotoMark(tags: ["beach"]), for: "a")
        marks.set(PhotoMark(tags: ["kids"]), for: "b")
        desk.run(.filterTag("beach"))
        desk.run(.filterTag("kids"))
        XCTAssertEqual(desk.filter.tags, ["beach", "kids"], "added, not replaced")
        let pick = MonitorMenu(desk).rows.first { $0.id == "triage.tagfilter" }
        guard case .pick(let p)? = pick?.step else { return XCTFail("a pick") }
        XCTAssertEqual(p.choices.filter(\.isCurrent).count, 2)
        DeskMenu.choose("turn filters off", on: desk)
        XCTAssertFalse(desk.filter.isActive)
    }

    func testMinimumStarsIsAFilter() {
        desk.run(.filterStars(4))
        XCTAssertEqual(desk.filter.minimumStars, 4)
    }

    // MARK: Settings

    func testAppearancePreviewsAndEscPutsItBack() {
        var state = desk.commandState(appearance: .light)
        state.appearance = .light
        var menu = CommandPalette(BestShotCommandList(state: state))
        menu.type("appearance")
        _ = menu.press(.enter)
        XCTAssertEqual(menu.lit?.title, "Light", "the one in force is lit first")
        _ = menu.takeEffects()
        _ = menu.press(.down)
        XCTAssertEqual(menu.takeEffects(), [.preview(.appearance(.dark))])
        _ = menu.press(.esc)
        XCTAssertEqual(menu.takeEffects(), [.revert(.appearance(.light))])
    }

    func testPauseSaysWhichWayItGoes() {
        XCTAssertTrue(MonitorMenu(desk).rows.contains { $0.title == "Pause monitor" })
        desk.run(.pause)
        XCTAssertTrue(desk.isPaused)
        let onPhone = BestShotCommandState.phone(place: .home, library: library, marks: marks, rank: nil,
                                                 monitorConnected: true, monitorPaused: desk.isPaused)
        XCTAssertTrue(rows(onPhone).contains { $0.title == "Resume monitor" })
    }

    func testTextSizeAndLabelNames() {
        let before = desk.textScale
        DeskMenu.choose("monitor text larger", on: desk)
        XCTAssertGreaterThan(desk.textScale, before)
        desk.run(.renameLabel(.green, "Select"))
        XCTAssertEqual(library.names[.green], "Select")
        XCTAssertEqual(MonitorMenu(desk).rows.first { $0.id == "photo.colour.green" }?.detail, "Select · 8")
        desk.adjustTextScale(-10)
    }

    // MARK: Each display has only what it draws

    func testTheMonitorHasNoPhoneScreens() {
        let ids = Set(everything(desk.commandState()).map(\.id))
        for id in ["go.joinvideos", "go.anticrop", "project.new", "photo.keep"] {
            XCTAssertFalse(ids.contains(id), id)
        }
    }

    func testThePhoneHasNoMonitorScreens() {
        let ids = Set(everything(phone(.triage)).map(\.id))
        for id in ["photo.zoom", "photo.compare", "triage.filters", "keys", "go.5"] {
            XCTAssertFalse(ids.contains(id), id)
        }
        XCTAssertTrue(ids.contains("photo.keep"))
        XCTAssertTrue(ids.contains("photo.colour.red"), "the same marks as the monitor")
    }

    func testThePhoneMarksItsOwnPhoto() {
        let state = phone(.triage)
        XCTAssertEqual(state.photo?.id, "a")
        desk.mark("a", with: .colour(.red))
        XCTAssertEqual(library.decision("a"), .deleted, "red waits to delete, as on the monitor")
        XCTAssertEqual(phone(.triage).photo?.colour, .red)
    }

    // MARK: Rank and Organise

    func testClearingTheRankingCanBeUndone() {
        let board = RankBoard(title: "t", media: Media(), pools: [RankPool(id: "p", title: "Kept", ids: ["a", "b", "c"])],
                              ranking: ["c", "a"], persist: { _ in })
        board.clear()
        XCTAssertEqual(board.ranked, [])
        let titles = rows(phone(.rank, rank: board)).map(\.title)
        XCTAssertTrue(titles.contains("Put the ranking back"))
        board.restoreCleared()
        XCTAssertEqual(board.ranked, ["c", "a"])
        XCTAssertFalse(rows(phone(.rank, rank: board)).contains { $0.title == "Put the ranking back" })
    }

    func testRankFromTheMenu() async {
        library.board = RankBoard(title: "t", media: Media(), pools: [RankPool(id: "p", title: "Kept", ids: ["a", "b", "c"])],
                                  ranking: ["a"], persist: { _ in })
        desk.run(.go(.rank))
        await desk.work?.value
        let titles = MonitorMenu(desk).rows.map(\.title)
        for title in ["Compare all", "Compare the unranked", "Save ranking as an album", "Clear ranking"] {
            XCTAssertTrue(titles.contains(title), title)
        }
        DeskMenu.choose("compare all", on: desk)
        await desk.work?.value
        XCTAssertEqual(desk.pane, .rankCompare)
        XCTAssertTrue(MonitorMenu(desk).rows.contains { $0.title == "Left is better" })
    }

    func testAddToAlbumIsAPickStep() async {
        library.organiseAlbums = [("a1", "Lisbon", false), ("a2", "Kids", true)]
        library.organisePhoto = "o1"
        desk.run(.go(.organise))
        XCTAssertEqual(desk.pane, .organise)
        var menu = MonitorMenu(desk)
        menu.type("add to album")
        XCTAssertEqual(menu.lit?.id, "organise.add")
        _ = menu.press(.enter)
        XCTAssertEqual(menu.depth, 1)
        XCTAssertEqual(menu.lit?.title, "Kids", "the album it's in is lit, with a tick")
        menu.type("lis")
        guard case .run(let action) = menu.press(.enter) else { return XCTFail("files it") }
        XCTAssertEqual(action, .addToAlbum("a1"))
        desk.run(action)
        await desk.work?.value
        XCTAssertEqual(library.filedInto, ["a1"])
    }

    // MARK: Projects

    func testProjectCommandsOnThePhone() {
        let id = UUID()
        let project = BestShotCommandState.OpenProject(id: id, name: "Wedding", count: 5, unranked: 2, sort: .nameAsc)
        var menu = CommandPalette(BestShotCommandList(state: phone(.project(id), project: project)))
        XCTAssertEqual(menu.sections.first?.title, "“Wedding”")
        menu.type("sort")
        _ = menu.press(.enter)
        XCTAssertEqual(menu.lit?.title, SortOption.nameAsc.title)
        let titles = menu.rows.map(\.title)
        XCTAssertEqual(titles, SortOption.allCases.map(\.title))

        var rename = CommandPalette(BestShotCommandList(state: phone(.project(id), project: project)))
        rename.type("rename")
        _ = rename.press(.enter)
        XCTAssertEqual(rename.query, "Wedding", "starts from the name")
        for _ in 0..<7 { rename.backspace() }
        rename.type("Party")
        XCTAssertEqual(rename.press(.enter), .run(.renameProject(id, "Party")))
    }
}
