import XCTest
import SwiftUI
@testable import BestShot

/// Stands in for Photos and the session. It counts what would reach the library.
@MainActor
final class FakeMonitorLibrary: MonitorLibrary {
    var hasPhotoAccess = true
    var canAskForPhotoAccess = false
    func askForPhotoAccess() async {}

    var triageIDs: [String] = []
    var triageIndex = 0
    var decisions: [String: ReviewDecision] = [:]
    var favourites = 0
    var triageWaiting: Int { decisions.values.filter { $0 == .deleted }.count }
    func decision(_ id: String) -> ReviewDecision { decisions[id] ?? .undecided }
    func setDecision(_ decision: ReviewDecision, _ id: String) { decisions[id] = decision }
    func isFavourite(_ id: String) -> Bool { false }
    func toggleFavourite() { favourites += 1 }

    var sources: [(option: TriageSourceOption, title: String)] = [(.allPhotos, "All Photos"), (.screenshots, "Screenshots")]
    func reloadSources() {}
    var nextSession: [String] = []
    func startTriage(order: SessionOrder, source: TriageSourceOption) async -> String? {
        triageIDs = nextSession
        return nextSession.isEmpty ? "Nothing found" : nil
    }
    var left = 0
    func leaveTriage() {
        left += 1
        if triageWaiting == 0 { triageIDs = [] }
    }
    func resumeTriage() {}
    var commits = 0
    var confirmsDelete = true
    func commitDeletions() async -> Int {
        commits += 1
        let waiting = decisions.filter { $0.value == .deleted }.map(\.key)
        if confirmsDelete { return waiting.count }
        // The session clears them on a turned-down confirmation.
        for id in waiting { decisions[id] = .undecided }
        return 0
    }
    func endTriage() {
        triageIDs = []
        decisions = [:]
    }
    func details(_ id: String) -> [String] { [] }

    func rankBoard() async -> RankBoard? { nil }
    func saveRankAlbum(_ ids: [String]) async -> String { "" }

    var organisePhoto: String?
    var organiseProgress = ""
    var organiseAlbums: [(id: String, title: String, added: Bool)] = []
    func startOrganise(order: SessionOrder, source: TriageSourceOption) async -> String? { nil }
    func addToAlbum(_ id: String) async {}
    func newAlbum(_ title: String) async {}
    func nextOrganised() {}
    func skipOrganised() {}
    func leaveOrganise() {}

    var projects: [(id: UUID, name: String, count: Int)] = []
    func media(project: UUID?) -> [MonitorMediaItem] {
        (0..<30).map { MonitorMediaItem(id: "m\($0)", title: "m\($0).jpg", detail: "", tags: []) }
    }

    var names: [LabelColour: String] = [:]
    func labelName(_ colour: LabelColour) -> String { names[colour] ?? colour.title }
    func renameLabel(_ colour: LabelColour, to name: String) -> String? {
        names[colour] = name
        return nil
    }
    var versionText = "1.0 (1)"

    func picture(_ id: String, longEdge: CGFloat, fill: Bool) -> AnyView { AnyView(Color.gray) }
    func warm(_ ids: [String], longEdge: CGFloat) {}
}

@MainActor
final class MonitorDeskTests: XCTestCase {
    private var library: FakeMonitorLibrary!
    private var url: URL!
    private var desk: MonitorDesk!

    override func setUp() async throws {
        library = FakeMonitorLibrary()
        library.triageIDs = ["a", "b", "c", "d"]
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("marks.json")
        desk = MonitorDesk(library: library, marks: PhotoMarkStore(url: url))
        desk.isConnected = true
        desk.setLocked(false)
        press(.enter) // Resume Triage, lit by default.
    }

    private func press(_ key: KeyName, _ mods: KeyMods = []) {
        desk.handle(MonitorPress(key, mods))
    }

    private func type(_ text: String) {
        for character in text { desk.handle(.typed(character)) }
    }

    private var currentMark: PhotoMark { desk.marks.mark(desk.current ?? "") }

    // MARK: The walk

    func testArrowsWalkAndStopAtTheEnds() {
        XCTAssertEqual(desk.pane, .loupe)
        XCTAssertEqual(desk.current, "a")
        press(.left)
        XCTAssertEqual(desk.current, "a")
        press(.right)
        XCTAssertEqual(desk.current, "b")
        for _ in 0..<10 { press(.right) }
        XCTAssertEqual(desk.current, "d")
        XCTAssertEqual(library.triageIndex, 3, "stays on the last photo and never runs off into the summary")
    }

    func testStarsAndClear() {
        type("4")
        XCTAssertEqual(currentMark.rating, 4)
        type("0")
        XCTAssertEqual(currentMark.rating, 0)
    }

    // MARK: Green good keep, yellow maybe, red delete

    func testGreenKeepsYellowIsMaybeRedWaitsToDelete() {
        type("8")
        XCTAssertEqual(desk.colour("a"), .green)
        XCTAssertEqual(library.decision("a"), .kept)
        XCTAssertEqual(desk.current, "a", "a colour stays on the photo, so a second press can clear it")
        press(.right)
        type("7")
        XCTAssertEqual(desk.colour("b"), .yellow)
        XCTAssertEqual(library.decision("b"), .skipped)
        press(.right)
        type("6")
        XCTAssertEqual(desk.colour("c"), .red)
        XCTAssertEqual(library.decision("c"), .deleted)
        XCTAssertEqual(library.commits, 0, "red only marks")
    }

    func testTheSameColourAgainClearsIt() {
        type("66")
        XCTAssertNil(desk.colour("a"))
        XCTAssertEqual(library.decision("a"), .undecided)
    }

    func testAKeptPhotoFromThePhoneShowsGreenAndADeletedOneRed() {
        library.decisions["a"] = .kept
        library.decisions["b"] = .deleted
        XCTAssertEqual(desk.colour("a"), .green)
        XCTAssertEqual(desk.colour("b"), .red)
    }

    func testUndoPutsBackTheMarkAndTheDecision() {
        type("6")
        press(.right)
        press(.char("z"), .command)
        XCTAssertEqual(desk.current, "a")
        XCTAssertNil(desk.colour("a"))
        XCTAssertEqual(library.decision("a"), .undecided)
    }

    // MARK: Delete

    func testNothingButTheFinishPanelReachesTheDelete() {
        type("6")
        // Every key on the board, with nothing chosen on purpose.
        let keys: [KeyName] = [.up, .left, .right, .enter, .tab, .backspace, .home, .end, .pageUp, .pageDown]
        for key in keys {
            press(key)
            press(key, .command)
        }
        for character in "abcdefghijklmnopqrstuvwyz0123456789[]\\" { desk.handle(.typed(character)) }
        XCTAssertEqual(library.commits, 0)
    }

    func testFinishStartsWithNothingChosenSoReturnDoesNothing() async {
        type("6x")
        press(.enter)
        await desk.work?.value
        XCTAssertEqual(library.commits, 0)
        guard case .finish = desk.overlay else { return XCTFail("the panel stays up") }
    }

    func testMenuCanOnlyOpenTheFinishPanel() async {
        type("6")
        press(.char("k"), .command)
        type("finish")
        press(.enter)
        await desk.work?.value
        XCTAssertEqual(library.commits, 0)
        guard case .finish(let finish) = desk.overlay else { return XCTFail("opens the panel") }
        XCTAssertNil(finish.chosen)
    }

    func testChoosingDeleteGoesThroughTheConfirmPathAndClearsUp() async {
        type("6")
        press(.right)
        type("3x")
        press(.down)
        press(.enter)
        await desk.work?.value
        XCTAssertEqual(library.commits, 1)
        XCTAssertNil(desk.overlay)
        XCTAssertEqual(desk.pane, .triage, "back to Triage's start, one press from the menu")
        XCTAssertEqual(desk.marks.mark("a"), PhotoMark(), "the deleted photo's mark goes with it")
        XCTAssertEqual(desk.marks.mark("b").rating, 3)
    }

    func testTurningDownTheConfirmationKeepsEveryMark() async {
        library.confirmsDelete = false
        type("6")
        press(.right)
        type("6x")
        press(.down)
        press(.enter)
        await desk.work?.value
        XCTAssertEqual(library.commits, 1)
        XCTAssertEqual(library.decision("a"), .deleted)
        XCTAssertEqual(library.decision("b"), .deleted)
        guard case .finish(let finish) = desk.overlay else { return XCTFail("the panel stays up") }
        XCTAssertNil(finish.chosen, "and has to be chosen again")
    }

    func testARedMarkTheSessionForgotComesBack() {
        type("6")
        library.decisions["a"] = .undecided
        type("x")
        XCTAssertEqual(library.decision("a"), .deleted)
    }

    func testAChoiceDoesntSurviveLockingOrPausing() async {
        type("6x")
        press(.down)
        desk.setLocked(true)
        desk.setLocked(false)
        press(.enter)
        await desk.work?.value
        XCTAssertEqual(library.commits, 0)
    }

    // MARK: Esc

    func testEscReachesHomeFromAnywhereInAFewPresses() {
        type("6z")                       // zoomed
        desk.handle(MonitorPress(.char("/"), .shift, text: "?"))
        XCTAssertEqual(desk.overlay, .help)
        var presses = 0
        while desk.stepBackFromEscape() {
            presses += 1
            XCTAssertLessThan(presses, 8)
        }
        XCTAssertEqual(desk.pane, .home, "the main menu")
        XCTAssertGreaterThan(library.left, 0)
        XCTAssertEqual(library.decision("a"), .deleted, "going home keeps what's marked")
        XCTAssertEqual(library.triageIDs.count, 4, "and the session waits behind Resume")
    }

    func testEscFromASectionIsOnePressHome() {
        press(.char("6"), .command)
        XCTAssertEqual(desk.pane, .settings)
        XCTAssertTrue(desk.stepBackFromEscape())
        XCTAssertEqual(desk.pane, .home)
    }

    func testEscAtHomeIsThePhones() {
        XCTAssertTrue(desk.stepBackFromEscape())
        XCTAssertEqual(desk.pane, .triage)
        XCTAssertTrue(desk.stepBackFromEscape())
        XCTAssertEqual(desk.pane, .home)
        XCTAssertFalse(desk.stepBackFromEscape())
    }

    func testHomeIsTheMainMenu() {
        while desk.stepBackFromEscape() {}
        XCTAssertEqual(desk.rows.map(\.title), MonitorSection.allCases.map(\.title))
        XCTAssertFalse(desk.keys.contains { $0.keys == "esc" }, "no Back in the hint bar at home")
        press(.down)
        press(.enter)
        XCTAssertEqual(desk.pane, .rank)
        XCTAssertTrue(desk.keys.contains { $0.keys == "esc" })
        XCTAssertTrue(desk.stepBackFromEscape())
        XCTAssertEqual(desk.pane, .home)
    }

    func testEscStackAsksTheMonitorAfterAPhoneSheetAndBeforeThePhone() {
        var log: [String] = []
        let stack = EscapeStack()
        stack.base = { log.append("home") }
        var monitorDepth = 1
        stack.monitorStep = {
            guard monitorDepth > 0 else { return false }
            monitorDepth -= 1
            log.append("monitor")
            return true
        }
        let screen = UUID(), sheet = UUID()
        stack.push(screen) {
            log.append("phone")
            stack.remove(screen)
        }
        stack.push(sheet, isSheet: true) {
            log.append("sheet")
            stack.remove(sheet)
        }
        for _ in 0..<4 { stack.press() }
        XCTAssertEqual(log, ["sheet", "monitor", "phone", "home"])
    }

    // MARK: Blank, paused, unplugged

    func testLockedShowsNoKeysAndNoKeyActs() {
        desk.setLocked(true)
        XCTAssertTrue(desk.keys.isEmpty)
        type("6")
        press(.right)
        desk.setLocked(false)
        XCTAssertEqual(desk.current, "a")
        XCTAssertNil(desk.colour("a"))
    }

    func testItStartsBlank() {
        let fresh = MonitorDesk(library: library, marks: desk.marks)
        XCTAssertTrue(fresh.isLocked)
    }

    func testPausedHoldsKeysUntilEscResumes() {
        press(.char("p"), [.command, .option])
        XCTAssertTrue(desk.isPaused)
        XCTAssertEqual(desk.situation.surface, .paused)
        type("6")
        XCTAssertNil(desk.colour("a"))
        XCTAssertTrue(desk.stepBackFromEscape())
        XCTAssertFalse(desk.isPaused)
        XCTAssertEqual(desk.pane, .loupe, "Esc resumes and goes no further")
    }

    func testUnpluggingLosesNothingAndKeysGoBackToThePhone() {
        type("6")
        press(.right)
        type("f")
        desk.isConnected = false
        desk.monitorLeft()
        XCTAssertFalse(desk.handle(.typed("6")))
        XCTAssertEqual(library.decision("a"), .deleted)
        desk.isConnected = true
        XCTAssertEqual(desk.pane, .filters)
        XCTAssertEqual(desk.marks.mark("a").colour, .red)
    }

    func testASheetOnThePhoneTakesTheKeysAndTheBarSaysSo() {
        desk.phoneSheetUp = true
        XCTAssertEqual(desk.keys.map(\.keys), ["esc"])
        XCTAssertFalse(desk.handle(.typed("6")))
        XCTAssertNil(desk.colour("a"))
    }

    // MARK: The hint bar

    func testTheBarIsTheTableTheKeysRunFrom() {
        // Everything the bar shows on the photo, by the press that fires it.
        let samples: [String: MonitorPress] = [
            "←→ jk": MonitorPress(.right), "Home End": MonitorPress(.home), "1–5 0": .typed("3"), "8": .typed("8"), "7": .typed("7"),
            "6": .typed("6"), "9": .typed("9"), "u": .typed("u"), "t": .typed("t"), "h": .typed("h"), "z": .typed("z"),
            "c": .typed("c"), "i": .typed("i"), "g": .typed("g"), "[ ]": .typed("]"), "f": .typed("f"),
            "x ⌘⌫": .typed("x"), "⌘K /": MonitorPress(.char("k"), .command), "⌘1–6 ⌘,": MonitorPress(.char("2"), .command),
            "?": MonitorPress(.char("/"), .shift, text: "?"), "esc": MonitorPress(.escape), "⌥⌘P": MonitorPress(.char("p"), [.command, .option]),
            "⌥⌘= −": MonitorPress(.char("="), [.command, .option]),
        ]
        let situation = desk.situation
        for binding in desk.keys {
            let sample = samples[binding.keys]
            XCTAssertNotNil(sample, "\(binding.keys) has no sample")
            if let sample {
                XCTAssertNotNil(MonitorKeymap.action(for: sample, in: situation), "\(binding.keys) doesn't run")
            }
        }
    }

    func testAKeyNotInTheBarDoesNothing() {
        XCTAssertNil(MonitorKeymap.action(for: .typed("q"), in: desk.situation))
        XCTAssertFalse(desk.keys.contains { $0.keys.contains("⌘Z") }, "nothing to undo yet")
        type("3")
        XCTAssertTrue(desk.keys.contains { $0.keys.contains("⌘Z") })
    }

    func testSharedKeysKeepTheirMeaning() {
        type("3")
        let situation = desk.situation
        func action(_ press: MonitorPress) -> MonitorAction? { MonitorKeymap.action(for: press, in: situation) }
        XCTAssertEqual(action(.typed("j")), .move(1))
        XCTAssertEqual(action(.typed("k")), .move(-1))
        XCTAssertEqual(action(MonitorPress(.char("z"), .command)), .undo)
        XCTAssertEqual(action(.typed("/")), .menu)
        XCTAssertEqual(action(MonitorPress(.char("1"), .command)), .section(.triage))
        XCTAssertEqual(action(.typed("x")), .finish, "x is Done: it opens Finish and never rejects")
    }

    func testHeldArrowsRepeatAndMarksDont() {
        XCTAssertTrue(desk.repeats(MonitorPress(.right)))
        XCTAssertFalse(desk.repeats(.typed("6")))
        XCTAssertFalse(desk.repeats(.typed("3")))
    }

    // MARK: Tags

    func testTypingATag() {
        type("t")
        type("beach8")
        XCTAssertNil(desk.colour("a"), "keys are letters while a tag is being typed")
        press(.enter)
        XCTAssertEqual(currentMark.tags, ["beach8"])
        XCTAssertNil(desk.overlay)
    }

    func testEscAddsATagBeingTypedAsTheViewerDoes() {
        type("tsea")
        XCTAssertTrue(desk.stepBackFromEscape())
        XCTAssertEqual(currentMark.tags, ["sea"])
        XCTAssertEqual(desk.pane, .loupe)
    }

    func testTabCompletesFromTagsInUseAndATagTypedAgainComesOff() {
        type("tsunset")
        press(.enter)
        press(.right)
        type("tsu")
        press(.tab)
        press(.enter)
        XCTAssertEqual(desk.marks.mark("b").tags, ["sunset"])
        type("tSUNSET")
        press(.enter)
        XCTAssertEqual(desk.marks.mark("b").tags, [])
    }

    // MARK: Filters, zoom, compare

    func testFilterNarrowsTheWalkAndHoldsAMarkedPhotoUntilYouMove() {
        type("8")
        press(.right)
        press(.right)
        type("8f")
        XCTAssertEqual(desk.pane, .filters)
        // Lit row starts at the top of the Show group: All, No colour, Green.
        press(.down)
        press(.down)
        press(.enter)
        XCTAssertTrue(desk.stepBackFromEscape())
        XCTAssertEqual(desk.visible, [0, 2])
        XCTAssertEqual(desk.current, "c")
        type("8")
        XCTAssertEqual(desk.current, "c", "no longer green, and held until you move on")
        press(.left)
        XCTAssertEqual(desk.current, "a")
        XCTAssertEqual(desk.visible, [0])
    }

    func testAnEmptyFilterHasNoPhotoAndMarksGoNowhere() {
        type("f")
        for _ in 0..<4 { press(.down) }
        press(.enter)
        XCTAssertTrue(desk.stepBackFromEscape())
        XCTAssertNil(desk.current)
        XCTAssertFalse(desk.handle(.typed("6")))
    }

    func testZoomThenArrowsPanAndEscLetsGo() {
        type("z")
        XCTAssertEqual(desk.zoom, 2)
        press(.right)
        XCTAssertEqual(desk.current, "a", "arrows pan while zoomed")
        XCTAssertGreaterThan(desk.pan.x, 0)
        XCTAssertTrue(desk.stepBackFromEscape())
        XCTAssertEqual(desk.zoom, 1)
        XCTAssertEqual(desk.pane, .loupe)
    }

    func testCompareHoldsOneAndWalksTheOther() {
        type("c")
        XCTAssertEqual(desk.pinned, "a")
        XCTAssertEqual(desk.current, "b")
        press(.right)
        XCTAssertEqual(desk.current, "c")
        type("8")
        XCTAssertEqual(desk.colour("c"), .green, "marks land on the right")
        press(.tab)
        XCTAssertEqual(desk.pinned, "c")
        XCTAssertEqual(desk.current, "a")
        XCTAssertTrue(desk.stepBackFromEscape())
        XCTAssertNil(desk.pinned)
    }

    func testGridMovesAndOpens() {
        desk.gridColumns = 2
        type("g")
        XCTAssertEqual(desk.pane, .grid)
        press(.down)
        XCTAssertEqual(desk.current, "c")
        type("6")
        XCTAssertEqual(library.decision("c"), .deleted)
        press(.enter)
        XCTAssertEqual(desk.pane, .loupe)
        XCTAssertEqual(desk.current, "c")
    }

    // MARK: Lists

    func testListsKeepALitRowAndPageThroughIt() {
        press(.char("4"), .command)
        XCTAssertEqual(desk.pane, .media(project: nil))
        XCTAssertEqual(desk.litRowID, "m0")
        press(.pageDown)
        XCTAssertEqual(desk.litRowID, "m10")
        press(.end)
        XCTAssertEqual(desk.litRowID, "m29")
        press(.enter)
        guard case .mediaPhoto = desk.pane else { return XCTFail("opens the photo") }
        press(.left)
        XCTAssertEqual(desk.mediaIndex, 28)
        XCTAssertTrue(desk.stepBackFromEscape())
        XCTAssertEqual(desk.litRowID, "m29", "the list is where it was left")
    }

    func testSettingsAreChangedFromTheKeyboard() {
        press(.char(","), .command)
        XCTAssertEqual(desk.pane, .settings)
        press(.down)
        press(.down)
        press(.enter) // Green, third colour.
        guard case .entry(let entry) = desk.overlay else { return XCTFail("asks for the name") }
        XCTAssertEqual(entry.text, "Green")
        for _ in 0..<5 { press(.backspace) }
        type("Select")
        press(.enter)
        XCTAssertEqual(library.names[.green], "Select")
    }

    func testMenuFiltersAndEscClosesInOnePress() {
        press(.char("k"), .command)
        type("set")
        guard case .palette(let palette) = desk.overlay else { return XCTFail("opens") }
        XCTAssertEqual(palette.lit?.title, "Settings")
        XCTAssertTrue(desk.stepBackFromEscape())
        XCTAssertNil(desk.overlay)
        XCTAssertEqual(desk.pane, .loupe)
    }

    func testMenuRunsAndCarriesOnFromThere() {
        press(.char("k"), .command)
        type("settings")
        press(.enter)
        XCTAssertEqual(desk.pane, .settings)
    }

    func testStartingFromHome() async {
        desk.stepBackFromEscape()
        library.triageIDs = []
        library.nextSession = ["x", "y"]
        XCTAssertEqual(desk.litRow?.action, .startTriage)
        press(.enter)
        await desk.work?.value
        XCTAssertEqual(desk.pane, .loupe)
        XCTAssertEqual(desk.current, "x")
    }

    func testTriageEndedOnThePhoneFallsBackToHome() {
        library.triageIDs = []
        XCTAssertEqual(desk.pane, .triage)
    }
}

@MainActor
final class PhotoMarkStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("marks.json")
    }

    func testMarksSurviveAReload() {
        let url = tempURL()
        let store = PhotoMarkStore(url: url)
        var mark = PhotoMark()
        mark.rating = 4
        mark.colour = .yellow
        mark.tags = ["sea"]
        store.set(mark, for: "a")
        store.flush()
        XCTAssertEqual(PhotoMarkStore(url: url).mark("a"), mark)
    }

    func testAnUnreadableFileIsMovedAsideNotWrittenOver() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = PhotoMarkStore(url: url)
        XCTAssertNotNil(store.warning)
        XCTAssertTrue(store.marks.isEmpty)
        var mark = PhotoMark()
        mark.rating = 1
        store.set(mark, for: "a")
        store.flush()
        let files = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        let aside = try XCTUnwrap(files.first { $0.contains("unreadable") })
        let kept = try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(aside))
        XCTAssertEqual(String(decoding: kept, as: UTF8.self), "not json")
    }

    func testMissingIsEmptyWithNoWarning() {
        let store = PhotoMarkStore(url: tempURL())
        XCTAssertNil(store.warning)
        XCTAssertTrue(store.marks.isEmpty)
    }

    func testAnEmptyMarkLeavesNothingBehind() {
        let store = PhotoMarkStore(url: tempURL())
        var mark = PhotoMark()
        mark.rating = 2
        store.set(mark, for: "a")
        store.set(PhotoMark(), for: "a")
        XCTAssertTrue(store.marks.isEmpty)
    }
}
