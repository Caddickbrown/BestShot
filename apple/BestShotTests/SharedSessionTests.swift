import XCTest
import SwiftUI
import SwiftData
@testable import BestShot

/// Dan, 17 Nov: "I think BestShot should be the same on the screen and the
/// monitor." The phone's Organise and the monitor's are one session, and Rank
/// is one board, as Triage already was.
@MainActor
final class SharedOrganiseTests: XCTestCase {
    private var container: ModelContainer!
    private var holder: OrganiseHolder!
    private var monitor: MonitorPhotosLibrary!
    private var folder: URL!
    private var files: [URL] = []

    override func setUp() async throws {
        container = try ModelContainer(for: Project.self, MediaItem.self, AssetReview.self, RankedOrder.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        holder = OrganiseHolder()
        monitor = MonitorPhotosLibrary(context: container.mainContext, triage: TriageHolder(), organise: holder, rank: RankHolder())
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        files = try ["a.jpg", "b.jpg", "c.jpg"].map {
            let url = folder.appendingPathComponent($0)
            try Data().write(to: url)
            return url
        }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The phone's Organise screen starts one, as it does from a folder in Files.
    @discardableResult
    private func phoneStarts() -> OrganiseSession {
        let session = OrganiseSession(files: files, folder: folder, albums: [], context: container.mainContext)
        holder.start(session)
        return session
    }

    private func id(_ i: Int) -> String { OrganiseItem.file(files[i]).id }

    func testTheMonitorIsOnThePhonesSession() {
        phoneStarts()
        XCTAssertTrue(monitor.organiseOpen)
        XCTAssertEqual(monitor.organisePhoto, id(0))
        XCTAssertTrue(monitor.organiseProgress.hasPrefix("1 / 3"), monitor.organiseProgress)
    }

    func testAStepOnEitherMovesBoth() {
        let phone = phoneStarts()
        monitor.skipOrganised()
        XCTAssertEqual(phone.index, 1, "the monitor's step is the phone's")
        phone.skip()
        XCTAssertEqual(monitor.organisePhoto, id(2), "and the phone's is the monitor's")
    }

    func testOneUndoHistoryNothingTakenBackTwice() async {
        let phone = phoneStarts()
        phone.skip()
        monitor.skipOrganised()
        XCTAssertTrue(monitor.organiseCanUndo)
        _ = await monitor.undoOrganise()
        XCTAssertEqual(phone.index, 1, "⌘Z on the monitor takes back the last step, whoever took it")
        await phone.undo()
        XCTAssertEqual(phone.index, 0)
        XCTAssertFalse(monitor.organiseCanUndo)
        let again = await monitor.undoOrganise()
        XCTAssertNil(again, "nothing left to take back")
        XCTAssertEqual(phone.index, 0)
    }

    func testLeavingWaitsToBeResumedWithItsUndo() {
        let phone = phoneStarts()
        phone.skip()
        monitor.leaveOrganise()
        XCTAssertTrue(holder.paused)
        XCTAssertFalse(monitor.organiseOpen)
        XCTAssertTrue(holder.session === phone, "the place is kept")
        holder.resume()   // the phone's Resume
        XCTAssertTrue(monitor.organiseOpen)
        XCTAssertEqual(monitor.organisePhoto, id(1))
        XCTAssertTrue(monitor.organiseCanUndo)
    }

    func testAFinishedSessionEnds() {
        let phone = phoneStarts()
        for _ in files { phone.skip() }
        monitor.leaveOrganise()
        XCTAssertNil(holder.session)
        XCTAssertNil(monitor.organisePhoto)
    }

    func testStartingAgainReplacesIt() {
        let first = phoneStarts()
        first.skip()
        holder.leave()
        let second = phoneStarts()
        XCTAssertFalse(holder.paused)
        XCTAssertTrue(holder.session === second)
        XCTAssertEqual(monitor.organisePhoto, id(0))
        XCTAssertFalse(monitor.organiseCanUndo, "a new session's Undo starts empty")
    }
}

@MainActor
final class SharedRankTests: XCTestCase {
    private final class Media: RankMedia {
        func thumbnail(_ id: String) -> AnyView { AnyView(Color.gray) }
        func fullImage(_ id: String) -> AnyView { AnyView(Color.gray) }
        func caption(_ id: String) -> String { id }
    }

    private var holder: RankHolder!
    private var reads = 0
    private var saved: [[String]] = []

    override func setUp() async throws {
        holder = RankHolder()
        reads = 0
        saved = []
    }

    private func board(_ ids: [String]) -> RankBoard {
        holder.board(kept: ids) {
            self.reads += 1
            return (["b"], { self.saved.append($0) })
        }
    }

    func testThePhoneAndTheMonitorGetOneBoard() {
        let phone = board(["a", "b", "c"])
        let monitor = board(["a", "b", "c"])
        XCTAssertTrue(phone === monitor)
        XCTAssertEqual(reads, 1, "the saved order is read once")
        XCTAssertEqual(monitor.ranked, ["b"])
    }

    func testANewKeeperJoinsWithoutStoppingACompare() {
        let phone = board(["a", "b"])
        phone.startCompare(scope: .all)
        let run = phone.compare
        XCTAssertNotNil(run)
        let monitor = board(["a", "b", "c"])
        XCTAssertTrue(monitor.compare === run, "the same pair is up on both")
        XCTAssertEqual(monitor.pool, ["a", "b", "c"])
    }

    func testADragIsSavedOnce() {
        let phone = board(["a", "b", "c"])
        let monitor = board(["a", "b", "c"])
        phone.move("a", before: "b")
        XCTAssertEqual(monitor.ranked, ["a", "b"])
        XCTAssertEqual(saved, [["a", "b"]])
    }
}

/// The monitor follows the shared sessions on its own screens.
@MainActor
final class MonitorFollowsThePhoneTests: XCTestCase {
    private var library: FakeMonitorLibrary!
    private var desk: MonitorDesk!

    override func setUp() async throws {
        library = FakeMonitorLibrary()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("marks.json")
        desk = MonitorDesk(library: library, marks: PhotoMarkStore(url: url))
        desk.isConnected = true
        desk.setLocked(false)
    }

    private func press(_ key: KeyName, _ mods: KeyMods = []) {
        desk.handle(MonitorPress(key, mods))
    }

    private func startOrganisingHere() async {
        press(.char("3"), .command)
        press(.end)
        press(.enter)
        await desk.work?.value
        XCTAssertEqual(desk.pane, .organise)
    }

    func testDoneOnThePhoneTakesTheMonitorToTheStartToo() async {
        await startOrganisingHere()
        library.leaveOrganise()   // Done on the phone
        XCTAssertEqual(desk.pane, .organiseHome)
        XCTAssertEqual(desk.rows.first { $0.id == "resume-organise" }?.action, .resumeOrganise)
        press(.escape)
        XCTAssertEqual(desk.pane, .home, "one Esc from what's showing")
    }

    func testEscOnTheMonitorLeavesThePhoneWaitingToo() async {
        await startOrganisingHere()
        press(.escape)
        XCTAssertEqual(desk.pane, .organiseHome)
        XCTAssertTrue(library.organisePaused, "the phone shows its start screen with Resume")
        XCTAssertEqual(desk.litRowID, "resume-organise")
        press(.enter)
        XCTAssertEqual(desk.pane, .organise)
        XCTAssertFalse(library.organisePaused, "resumed here, resumed on the phone")
    }

    func testStartedOnThePhoneComesUpHere() {
        XCTAssertEqual(desk.pane, .home)
        library.organisePhoto = "asset-1"
        desk.phoneOpened(.organise)
        XCTAssertEqual(desk.pane, .organise)
        XCTAssertFalse(library.organisePaused)
        press(.escape)
        XCTAssertEqual(desk.pane, .organiseHome, "with its start screen under it")
    }

    // Triage, as Organise: started or resumed on the phone, it's up on the monitor too (Dan, 17 Nov).

    func testTriageStartedOnThePhoneComesUpHere() {
        library.triageIDs = ["asset-1", "asset-2"]
        desk.phoneOpened(.triage)
        XCTAssertEqual(desk.pane, .loupe)
        press(.right)
        XCTAssertEqual(library.triageIndex, 1, "the monitor's keys move the phone's session")
        press(.escape)
        XCTAssertEqual(desk.pane, .triage, "with its start screen under it")
    }

    func testTriageLeftOnThePhoneTakesTheMonitorToItsStart() {
        library.triageIDs = ["asset-1", "asset-2"]
        desk.phoneOpened(.triage)
        library.triagePaused = true   // Done on the phone, with photos marked
        XCTAssertEqual(desk.pane, .triage)
        press(.escape)
        XCTAssertEqual(desk.pane, .home, "one Esc from what's showing")
    }

    func testTriageAlreadyUpHereStaysWhereItIs() {
        library.triageIDs = ["asset-1", "asset-2"]
        desk.phoneOpened(.triage)
        press(.char("g"))
        let here = desk.pane
        desk.phoneOpened(.triage)
        XCTAssertEqual(desk.pane, here, "the phone resuming doesn't pull the monitor off its grid")
    }

    func testNoMonitorTriageStaysOnThePhone() {
        desk.isConnected = false
        library.triageIDs = ["asset-1"]
        desk.phoneOpened(.triage)
        XCTAssertEqual(desk.pane, .home)
    }

    func testNoMonitorNothingFollows() {
        desk.isConnected = false
        library.organisePhoto = "asset-1"
        desk.phoneOpened(.organise)
        XCTAssertEqual(desk.pane, .home)
    }

    private func sharedBoard() -> RankBoard {
        let holder = RankHolder()
        let board = holder.board(kept: ["a", "b", "c"]) { ([], { _ in }) }
        library.board = board
        return board
    }

    func testACompareStartedOnThePhoneIsUpHereAndOneAnswerCounts() async {
        let board = sharedBoard()
        press(.char("2"), .command)
        await desk.work?.value
        XCTAssertEqual(desk.pane, .rank)
        board.startCompare(scope: .all)   // on the phone
        XCTAssertEqual(desk.pane, .rankCompare)
        press(.left)
        XCTAssertEqual(board.compare?.progress.asked, 1, "the monitor's answer is the phone's, once")
        press(.escape)
        XCTAssertNil(board.compare, "saved and closed on both")
        XCTAssertEqual(desk.pane, .rank, "back to Rank, not past it")
    }

    func testThePhonesCompareBringsUpRank() async {
        let board = sharedBoard()
        board.startCompare(scope: .all)
        desk.phoneOpened(.rank)
        await desk.work?.value
        XCTAssertEqual(desk.pane, .rankCompare)
    }

    func testAComparedFinishedOnThePhoneLeavesRankHere() async {
        let board = sharedBoard()
        press(.char("2"), .command)
        await desk.work?.value
        press(.char("c"))
        if desk.pane != .rankCompare { board.startCompare(scope: .all) }
        XCTAssertEqual(desk.pane, .rankCompare)
        board.finishCompare(save: true)   // Save & exit on the phone
        XCTAssertEqual(desk.pane, .rank)
        press(.escape)
        XCTAssertEqual(desk.pane, .home, "one Esc from Rank")
    }
}
